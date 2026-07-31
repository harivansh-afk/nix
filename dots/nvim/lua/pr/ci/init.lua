-- pr.ci: the CI store - one cache, one poller, many subscribers.
--
-- Entries are keyed on the COMMIT SHA, never the PR number, for the same
-- reason pr.data keys its diff caches on resolved shas: a force-push means a
-- new sha means a new key, so invalidation is structural rather than
-- bookkeeping. The pane and the pr://list orbs both read this store, so the
-- two surfaces cannot disagree about a check.
--
-- Nothing here draws. pr.ci.pane renders an entry; this decides what an
-- entry IS and when it is worth asking the forge again.

local api = require "pr.ci.api"
local data = require "pr.data"

local M = {}

-- ---------------------------------------------------------------- buckets ---
-- GitHub and Gitea between them spell about twenty status and conclusion
-- values. They collapse to six, and everything above this file speaks only
-- in buckets. Unknown values are pending, never passing: both enums are open
-- and a new one must not render as a green tick.

local BUCKET = {
  success = "pass",

  failure = "fail",
  startup_failure = "fail",
  timed_out = "fail",
  error = "fail",

  action_required = "attention",
  blocked = "attention",

  in_progress = "running",
  running = "running",

  queued = "pending",
  requested = "pending",
  waiting = "pending",
  pending = "pending",
  expected = "pending",

  skipped = "skipped",
  neutral = "skipped",
  stale = "skipped",
  cancelled = "skipped",
}

--- The orb vocabulary. Shapes distinguish what colour alone cannot (a queued
--- job from a running one); the highlight groups are the SAME Diagnostic*
--- family the pr://list orbs already use, so the palette is one palette.
M.SYM = { pass = "✓", fail = "✗", running = "●", pending = "○", skipped = "⊘", attention = "!" }
M.HL = {
  pass = "DiagnosticOk",
  fail = "DiagnosticError",
  running = "DiagnosticWarn",
  pending = "Comment",
  skipped = "Comment",
  attention = "DiagnosticWarn",
}
M.RANK = { fail = 1, attention = 2, running = 3, pending = 4, pass = 5, skipped = 6 }

--- Both CI surfaces put their summary in the winbar, and the default WinBar
--- is a slab: cozybox paints it #1d2021 focused and #3c3836 UNfocused, over a
--- #101010 Normal. A pane you glance at is unfocused almost all the time, so
--- the header sat there as a grey block under the diff.
---
--- Flush with Normal instead. There is already a separator above the pane -
--- the upper window's statusline - so a second band buys nothing, and every
--- winbar segment carries its own group, so the text keeps its colour and
--- only the background goes away. A link (not a copy) follows a light/dark
--- switch for free, and `default` leaves it overridable from a colourscheme.
---
--- Applied per WINDOW via 'winhighlight', never by redefining WinBar: this
--- is the pane's opinion about its own header, not about the user's editor.
M.WINBAR = "WinBar:PrCiWinBar,WinBarNC:PrCiWinBar"

function M.setup_hls() vim.api.nvim_set_hl(0, "PrCiWinBar", { link = "Normal", default = true }) end

---@return "pass"|"fail"|"running"|"pending"|"skipped"|"attention"
function M.bucket(status, conclusion)
  local c = conclusion and tostring(conclusion):lower() or nil
  local s = status and tostring(status):lower() or nil
  if c and c ~= "" then return BUCKET[c] or "pending" end
  if s and s ~= "" then return BUCKET[s] or "pending" end
  return "pending"
end

---@return boolean  is this job still going to change?
local function live(bucket) return bucket == "running" or bucket == "pending" end

-- --------------------------------------------------------------- duration ---

--- Seconds this job has been going, or took. nil when the forge told us
--- nothing worth printing: a finished job whose times were inherited from
--- its run would report the RUN's duration as its own, so it reports
--- nothing and the winbar's total stands in.
---@return integer? seconds
function M.elapsed(job)
  if not job.started_at then return nil end
  if live(job.bucket) then return math.max(0, api.now() - job.started_at) end
  if job.inherited or not job.finished_at then return nil end
  return math.max(0, job.finished_at - job.started_at)
end

--- "4s", "39s", "1m12s", "1h03m" - the compact form pr.fmt.ago uses for ages.
---@param s integer?
function M.dur(s)
  if not s then return "" end
  if s < 60 then return s .. "s" end
  if s < 3600 then return ("%dm%02ds"):format(s / 60, s % 60) end
  return ("%dh%02dm"):format(s / 3600, (s % 3600) / 60)
end

-- ------------------------------------------------------------------ store ---

---@class pr.ci.Entry
---@field sha string
---@field root string
---@field state "loading"|"ready"|"error"
---@field err string?
---@field jobs table[]
---@field counts table<string, integer>
---@field rollup string?  worst bucket present
---@field fetched_at integer?
---@field live_since integer?  when this entry first had something in flight

local entries = {} ---@type table<string, pr.ci.Entry>
local subs = {} ---@type table<string, table<integer, function>>
local timers = {} ---@type table<string, uv.uv_timer_t>
local gens = {} ---@type table<string, integer>
local sub_id = 0
local paused = false

--- Poll cadence. These are chosen defaults, not measured optima: fast enough
--- that a 30s job visibly finishes, slow enough that a 20-minute build does
--- not make 240 requests. The backoff exists because a long run's remaining
--- time is long - checking it every 5s tells you nothing new.
local POLL = {
  { after = 0, every = 5000 },
  { after = 120, every = 10000 },
  { after = 600, every = 30000 },
}

local function interval(entry)
  local age = entry.live_since and (api.now() - entry.live_since) or 0
  local every = POLL[1].every
  for _, step in ipairs(POLL) do
    if age >= step.after then every = step.every end
  end
  return every
end

local function stop(sha)
  local t = timers[sha]
  if t then
    t:stop()
    if not t:is_closing() then t:close() end
    timers[sha] = nil
  end
end

--- Drop an entry nobody is watching, so a session that steps through fifty
--- PRs does not keep fifty check lists alive.
local function release(sha)
  stop(sha)
  subs[sha], entries[sha], gens[sha] = nil, nil, nil
end

local function notify(sha)
  local e = entries[sha]
  for _, cb in pairs(subs[sha] or {}) do
    pcall(cb, e)
  end
end

local function watching(sha) return next(subs[sha] or {}) ~= nil end

local fetch, schedule

--- Arm the timer iff there is something in flight AND someone is watching.
--- Everything terminal means no timer at all - the pane sitting on a merged
--- PR's green checks costs nothing.
function schedule(sha)
  local e = entries[sha]
  stop(sha)
  if paused or not e or not watching(sha) then return end
  if (e.counts.running or 0) + (e.counts.pending or 0) == 0 then
    e.live_since = nil
    return
  end
  e.live_since = e.live_since or api.now()
  local t = assert(vim.uv.new_timer())
  timers[sha] = t
  t:start(
    interval(e),
    0,
    vim.schedule_wrap(function()
      if watching(sha) then fetch(e.root, sha) end
    end)
  )
end

---@param jobs table[]
local function summarize(entry, jobs)
  local counts, worst = {}, nil
  for i, j in ipairs(jobs) do
    j.bucket = M.bucket(j.status, j.conclusion)
    j.ord = i
    counts[j.bucket] = (counts[j.bucket] or 0) + 1
    if not worst or M.RANK[j.bucket] < M.RANK[worst] then worst = j.bucket end
  end
  -- Worst bucket first, so a failure is always at the top of the pane where
  -- a three-line window still shows it. Within a bucket the FORGE's order
  -- wins: it is dependency order (Forgejo even hands back `needs`), which
  -- reads far better than alphabetical for a run of green ticks.
  table.sort(jobs, function(a, b)
    if a.bucket ~= b.bucket then return M.RANK[a.bucket] < M.RANK[b.bucket] end
    if (a.workflow or "") ~= (b.workflow or "") then return (a.workflow or "") < (b.workflow or "") end
    return a.ord < b.ord
  end)
  entry.jobs, entry.counts, entry.rollup = jobs, counts, worst
end

--- A generation counter per sha drops a response that lands after the answer
--- it would overwrite - the same guard pr.list uses across an R mid-flight.
function fetch(root, sha)
  gens[sha] = (gens[sha] or 0) + 1
  local gen = gens[sha]
  local e = entries[sha] or { sha = sha, root = root, state = "loading", jobs = {}, counts = {} }
  entries[sha] = e
  api.checks(root, data.forge(root), sha, function(jobs, err)
    if gens[sha] ~= gen then return end
    e.fetched_at = api.now()
    if err then
      e.state, e.err = "error", err
    else
      e.state, e.err = "ready", nil
      summarize(e, jobs or {})
    end
    notify(sha)
    schedule(sha)
  end)
  return e
end

--- Watch a commit's checks. `cb(entry)` fires on the first answer and on
--- every change after it; the returned function unsubscribes.
---@param cb fun(entry: pr.ci.Entry)
---@return fun() unwatch
function M.watch(root, sha, cb)
  subs[sha] = subs[sha] or {}
  sub_id = sub_id + 1
  local id = sub_id
  subs[sha][id] = cb

  local e = entries[sha]
  if e then
    vim.schedule(function()
      if subs[sha] and subs[sha][id] then cb(e) end
    end)
    schedule(sha)
  else
    fetch(root, sha)
  end

  return function()
    if not subs[sha] then return end
    subs[sha][id] = nil
    if not watching(sha) then release(sha) end
  end
end

---@return pr.ci.Entry?
function M.get(sha) return entries[sha] end

--- Force a re-fetch now, whatever the poller was planning. This is what R
--- and `:e` mean on the pane.
function M.refresh(root, sha) return fetch(root, sha) end

--- PR number -> rollup state for every open PR, in one call. The pr://list
--- orbs read this; see the note in pr.ci.api about why it is a separate path
--- from the per-sha detail.
---@param cb fun(map?: table<integer, string>, err?: string)
function M.rollup_all(root, cb) api.rollup_all(root, data.forge(root), cb) end

-- ------------------------------------------------------------------ focus ---
-- Polling a forge while nvim is not the focused window is pure waste: there
-- is nobody looking at the answer. Suspend on blur, and resume with an
-- immediate fetch so the pane is already correct when you look back at it.

vim.api.nvim_create_autocmd("FocusLost", {
  group = vim.api.nvim_create_augroup("pr_ci_focus", { clear = true }),
  callback = function()
    paused = true
    for sha in pairs(timers) do
      stop(sha)
    end
  end,
})

vim.api.nvim_create_autocmd("FocusGained", {
  group = "pr_ci_focus",
  callback = function()
    paused = false
    for sha, e in pairs(entries) do
      if watching(sha) then fetch(e.root, sha) end
    end
  end,
})

return M
