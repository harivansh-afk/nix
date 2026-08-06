-- pr.threads: the conversation store - one cache, one poller, many
-- subscribers. The same engine shape as pr.ci, with ONE deliberate
-- divergence: entries are keyed on the PR NUMBER, not a sha. A conversation
-- belongs to the PR and mutates in place - replies, edits and resolves all
-- survive a force-push - so invalidation is temporal (the poll, and R),
-- where the CI store's is structural. Keying on the head sha would orphan
-- every thread the moment the author pushes.
--
-- The other simplification falls out of the domain: comments have no
-- "in flight" state to chase, so there is no backoff ladder and no two
-- depths - one flat cadence while somebody is watching, one full read
-- per fetch. Nothing here draws; pr.threads.pane renders an entry.

local api = require "pr.threads.api"
local data = require "pr.data"

local M = {}

-- ------------------------------------------------------------------ ranks ---
-- What the pane shows first. Unresolved code threads are the actionable
-- thing (the codex review you came to answer), a requested-changes verdict
-- is why they exist, chatter follows, and everything settled sinks dim to
-- the bottom.

M.SYM = { thread = "●", changes = "✗", commented = "○", comment = "○", approved = "✓", settled = "⊘" }
M.HL = {
  thread = "DiagnosticWarn",
  changes = "DiagnosticError",
  commented = "Comment",
  comment = "Comment",
  approved = "DiagnosticOk",
  settled = "Comment",
}

--- The face an item wears: its SYM/HL key, which is also its sort class.
---@return string
function M.face(item)
  if item.kind == "thread" then return (item.resolved or item.outdated) and "settled" or "thread" end
  if item.kind == "review" then return item.dismissed and "settled" or item.verdict end
  return "comment"
end

local RANK = { thread = 1, changes = 2, commented = 3, comment = 3, approved = 4, settled = 5 }

-- ------------------------------------------------------------------ store ---

---@class pr.threads.Entry
---@field key string
---@field root string
---@field number integer
---@field state "loading"|"ready"|"error"
---@field err string?
---@field items table[]
---@field counts table<string, integer>  face -> n
---@field fetched_at integer?

local entries = {} ---@type table<string, pr.threads.Entry>
local subs = {} ---@type table<string, table<integer, function>>
local timers = {} ---@type table<string, uv.uv_timer_t>
local gens = {} ---@type table<string, integer>
local sub_id = 0
local paused = false

--- One flat cadence: a conversation moves at human speed, so 30s is fresh
--- enough to catch a codex review landing while never hammering the forge -
--- and the timer only exists while a pane is actually watching.
local EVERY = 30000

local function key_of(root, number) return root .. "\0" .. number end

local function stop(key)
  local t = timers[key]
  if t then
    t:stop()
    if not t:is_closing() then t:close() end
    timers[key] = nil
  end
end

local function release(key)
  stop(key)
  subs[key], entries[key], gens[key] = nil, nil, nil
end

local function notify(key)
  local e = entries[key]
  for _, cb in pairs(subs[key] or {}) do
    pcall(cb, e)
  end
end

local function watching(key) return next(subs[key] or {}) ~= nil end

local fetch

local function schedule(key)
  local e = entries[key]
  stop(key)
  if paused or not e or not watching(key) then return end
  local t = assert(vim.uv.new_timer())
  timers[key] = t
  t:start(
    EVERY,
    0,
    vim.schedule_wrap(function()
      if watching(key) then fetch(e.root, e.number) end
    end)
  )
end

---@param items table[]
local function summarize(entry, items)
  local counts = {}
  for i, it in ipairs(items) do
    it.face = M.face(it)
    it.ord = i
    counts[it.face] = (counts[it.face] or 0) + 1
  end
  -- Actionable first; within a class, OLDEST first - a conversation reads
  -- top to bottom, and the settled tail keeps the same reading order.
  table.sort(items, function(a, b)
    if RANK[a.face] ~= RANK[b.face] then return RANK[a.face] < RANK[b.face] end
    if (a.ts or 0) ~= (b.ts or 0) then return (a.ts or 0) < (b.ts or 0) end
    return a.ord < b.ord
  end)
  entry.items, entry.counts = items, counts
end

--- Primed-but-unwatched entries linger as cache; a modest cap keeps a long
--- session honest. Watched entries are live state, never dropped.
local ENTRIES_MAX = 64

local function ensure(root, number)
  local key = key_of(root, number)
  local e = entries[key]
  if e then return e end
  local n = 0
  for _ in pairs(entries) do
    n = n + 1
  end
  if n >= ENTRIES_MAX then
    for k in pairs(entries) do
      if not watching(k) then
        stop(k)
        entries[k], gens[k] = nil, nil
      end
    end
  end
  e = { key = key, root = root, number = number, state = "loading", items = {}, counts = {} }
  entries[key] = e
  return e
end

--- A generation counter per key drops a response that lands after the answer
--- it would overwrite - the same guard every fetch in this plugin wears.
function fetch(root, number)
  local key = key_of(root, number)
  gens[key] = (gens[key] or 0) + 1
  local gen = gens[key]
  local e = ensure(root, number)
  api.talk(root, data.forge(root), number, function(items, err)
    if gens[key] ~= gen then return end
    e.fetched_at = os.time()
    if err then
      e.state, e.err = "error", err
    else
      e.state, e.err = "ready", nil
      summarize(e, items or {})
    end
    notify(key)
    schedule(key)
  end)
  return e
end

--- Watch a PR's conversation. `cb(entry)` fires on the first answer and on
--- every change after it; the returned function unsubscribes.
---@param cb fun(entry: pr.threads.Entry)
---@return fun() unwatch
function M.watch(root, number, cb)
  local key = key_of(root, number)
  subs[key] = subs[key] or {}
  sub_id = sub_id + 1
  local id = sub_id
  subs[key][id] = cb

  local e = entries[key]
  if e and e.state == "ready" then
    vim.schedule(function()
      if subs[key] and subs[key][id] then cb(e) end
    end)
    schedule(key)
  else
    fetch(root, number)
  end

  return function()
    if not subs[key] then return end
    subs[key][id] = nil
    if not watching(key) then release(key) end
  end
end

---@return pr.threads.Entry?
function M.get(root, number) return entries[key_of(root, number)] end

--- Force a re-fetch now, whatever the poller was planning: R and `:e`.
function M.refresh(root, number) return fetch(root, number) end

-- ------------------------------------------------------------------ focus ---
-- Same policy as the CI store: polling a forge nobody is looking at is pure
-- waste. Suspend on blur, resume with an immediate fetch.

vim.api.nvim_create_autocmd("FocusLost", {
  group = vim.api.nvim_create_augroup("pr_threads_focus", { clear = true }),
  callback = function()
    paused = true
    for key in pairs(timers) do
      stop(key)
    end
  end,
})

vim.api.nvim_create_autocmd("FocusGained", {
  group = "pr_threads_focus",
  callback = function()
    paused = false
    for key, e in pairs(entries) do
      if watching(key) then fetch(e.root, e.number) end
    end
  end,
})

return M
