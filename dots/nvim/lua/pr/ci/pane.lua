-- pr.ci.pane: pr://checks - the CI state of the loaded PR, one row per job.
--
-- A bottom split under pr://files, not a float: every other surface in this
-- plugin is a real buffer in a real window, and <c-w> should reach this one
-- the same way. The summary lives in the WINBAR rather than in header rows,
-- because the pane is small and the PR header is already on screen above it.
--
-- Row layout mirrors the two existing surfaces exactly:
--   orb + name as real text, meta right-aligned as virtual text - the same
--   shape pr.view uses for "+18 -4" on a file row. That is also what makes
--   the elapsed column tick for free: a running job's timer rewrites ONE
--   extmark per second and never touches a line.
--
-- <Tab> expands a job in place (steps on GitHub, the live log tail on
-- Forgejo, which has no step API), <CR> opens the whole log - the same two
-- gestures, in the same order, as <Tab>/<CR> on a file row in pr://files.

local ci = require "pr.ci"
local data = require "pr.data"
local fmt = require "pr.fmt"

local M = {}

local ns = vim.api.nvim_create_namespace "pr_ci_pane"

local buf ---@type integer?
local unwatch ---@type fun()?
local sha, root ---@type string?, string?
local entry ---@type pr.ci.Entry?
local expanded = {} ---@type table<integer, true>
local rows = {} ---@type table<integer, table> lnum -> job
local vt = {} ---@type table<integer, integer> lnum -> virt-text extmark id
local ticker ---@type uv.uv_timer_t?

local MAX_HEIGHT = 12
local TAIL = 8 -- log lines a <Tab> shows for a job with no step API

local function warn(msg) vim.notify("pr: " .. msg, vim.log.levels.WARN) end

---@return integer? win  the window showing the pane, if any
local function pane_win()
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then return nil end
  local w = vim.fn.bufwinid(buf)
  return w ~= -1 and w or nil
end

function M.is_open() return pane_win() ~= nil end

-- ----------------------------------------------------------------- winbar ---

local function paint(hl, text) return ("%%#%s#%s%%*"):format(hl, text) end

--- "1 fail, 2 running, 9/12 passing" - worst bucket first, empty ones
--- omitted. Straight out of ci.nvim's status.summary.
local function summary(e)
  local total = #e.jobs
  if total == 0 then return paint("Comment", "no checks") end
  local parts = {}
  for _, b in ipairs { "fail", "attention", "running", "pending", "skipped" } do
    if (e.counts[b] or 0) > 0 then parts[#parts + 1] = paint(ci.HL[b], ("%d %s"):format(e.counts[b], b)) end
  end
  if #parts == 0 then return paint("DiagnosticOk", ("%d passing"):format(total)) end
  parts[#parts + 1] = paint("DiagnosticOk", ("%d/%d passing"):format(e.counts.pass or 0, total))
  return table.concat(parts, ", ")
end

--- Total wall time across the run, which is what the per-job column cannot
--- always give: Forgejo reports no per-job timing at all.
local function span(e)
  local first, last, now = nil, nil, nil
  for _, j in ipairs(e.jobs) do
    if j.started_at then first = math.min(first or j.started_at, j.started_at) end
    if j.bucket == "running" or j.bucket == "pending" then now = true end
    if j.finished_at then last = math.max(last or j.finished_at, j.finished_at) end
  end
  if not first then return nil end
  return ci.dur(math.max(0, (now and require("pr.ci.api").now() or last or first) - first))
end

local function winbar()
  local win = pane_win()
  if not win then return end
  local s = require("pr").state
  local bits = {}
  if s.pr then bits[#bits + 1] = paint("fugitiveCount", "#" .. s.pr.number) end
  if sha then bits[#bits + 1] = paint("fugitiveHash", sha:sub(1, 7)) end
  if entry then
    if entry.state == "error" then
      bits[#bits + 1] = paint("DiagnosticError", "error")
    elseif entry.state == "loading" then
      bits[#bits + 1] = paint("Comment", "loading")
    else
      bits[#bits + 1] = summary(entry)
      local t = span(entry)
      if t and t ~= "" then bits[#bits + 1] = paint("Comment", t) end
    end
  end
  vim.wo[win][0].winbar = " " .. table.concat(bits, paint("Comment", " · "))
end

-- ----------------------------------------------------------------- render ---

--- The right-aligned meta for one row: workflow, then elapsed. Kept as its
--- own extmark so the ticker can replace it without touching the line.
local function meta(job)
  local out = {}
  if job.workflow and job.workflow ~= "" then
    out[#out + 1] = { fmt.trunc(job.workflow, 20), "Comment" }
    out[#out + 1] = { "  " }
  end
  out[#out + 1] = { ci.dur(ci.elapsed(job)), job.bucket == "running" and "DiagnosticWarn" or "Comment" }
  out[#out + 1] = { " " }
  return out
end

local function set_meta(lnum, job)
  vt[lnum] = vim.api.nvim_buf_set_extmark(buf, ns, lnum - 1, 0, {
    id = vt[lnum],
    virt_text = meta(job),
    virt_text_pos = "right_align",
  })
end

--- One second is the resolution the elapsed column shows, so that is the
--- tick. It runs only while a job is actually in flight and the pane is
--- actually on screen, and it does no I/O whatsoever - the count is
--- arithmetic on a start time already in hand.
local function retick()
  local live = false
  for _, job in pairs(rows) do
    if job.bucket == "running" then live = true end
  end
  if live and M.is_open() then
    if ticker then return end
    ticker = assert(vim.uv.new_timer())
    ticker:start(
      1000,
      1000,
      vim.schedule_wrap(function()
        if not (M.is_open() and buf and vim.api.nvim_buf_is_valid(buf)) then return retick() end
        for lnum, job in pairs(rows) do
          if job.bucket == "running" then set_meta(lnum, job) end
        end
        winbar()
      end)
    )
  elseif ticker then
    ticker:stop()
    if not ticker:is_closing() then ticker:close() end
    ticker = nil
  end
end

--- Detail lines under an expanded job. GitHub hands over a real step list;
--- Forgejo has no step API, so an excerpt of the log stands in - which for a
--- RUNNING job is the more useful of the two anyway.
---
--- Truncation happens HERE rather than at fetch time, so a resized window
--- re-cuts the same lines instead of showing a stale width.
---@return {[1]:string,[2]:string}[]
local function detail(job)
  local out = {}
  local win = pane_win()
  local width = (win and vim.api.nvim_win_get_width(win) or vim.o.columns) - 6
  if job.steps then
    for _, s in ipairs(job.steps) do
      local b = ci.bucket(s.status, s.conclusion)
      out[#out + 1] = { ("    %s %s"):format(ci.SYM[b], fmt.trunc(s.name or "?", width)), ci.HL[b] }
    end
  elseif job.tail then
    for _, l in ipairs(job.tail) do
      out[#out + 1] = { "    " .. fmt.trunc(l, width), job.bucket == "fail" and "DiagnosticError" or "Comment" }
    end
  else
    out[#out + 1] = { "    ...", "Comment" }
  end
  if #out == 0 then out[#out + 1] = { "    (nothing to show yet)", "Comment" } end
  return out
end

local function render()
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then return end
  local lines, marks = {}, {}
  rows, vt = {}, {}
  local seg = fmt.segmenter(lines, marks, function(row, group, from, to) return { row, from, to, group } end)

  local e = entry
  if not e or e.state == "loading" then
    lines[1] = " loading checks..."
  elseif e.state == "error" then
    seg { { " ! ", "DiagnosticError" }, { e.err or "could not read checks" } }
  elseif #e.jobs == 0 then
    lines[1] = " no checks on " .. (sha and sha:sub(1, 7) or "this commit")
  else
    for _, job in ipairs(e.jobs) do
      seg { { " " }, { ci.SYM[job.bucket], ci.HL[job.bucket] }, { " " }, { job.name or "?" } }
      rows[#lines] = job
      if expanded[job.id or -1] then
        for _, d in ipairs(detail(job)) do
          lines[#lines + 1] = d[1]
          marks[#marks + 1] = { #lines - 1, 0, -1, d[2] }
        end
      end
    end
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false -- a render is a load, never an edit (:e checks this)

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, m in ipairs(marks) do
    local to = m[3] == -1 and #lines[m[1] + 1] or m[3]
    vim.api.nvim_buf_set_extmark(buf, ns, m[1], m[2], { end_col = to, hl_group = m[4] })
  end
  for lnum, job in pairs(rows) do
    set_meta(lnum, job)
  end

  local win = pane_win()
  if win then vim.api.nvim_win_set_height(win, math.max(1, math.min(#lines, MAX_HEIGHT))) end
  winbar()
  retick()
end

-- ---------------------------------------------------------------- actions ---

local function job_at() return rows[vim.fn.line "."] end

--- Fill in whatever an expanded row needs, then re-render. Runs at most one
--- request per job at a time; a running job's tail is re-read on every store
--- update, so an expanded row follows the log as it is written.
local function fill(job)
  if not job.id or job.busy then return end
  local api = require "pr.ci.api"
  local forge = data.forge(root)
  job.busy = true
  -- Unconditional on gh: steps ARE the expansion there, so re-reading them is
  -- how a running job's expanded row advances. Gating on `not job.steps` froze
  -- the steps after the first fetch and then fell through to the log below,
  -- which gh never shows for an expanded job - a wasted request per poll.
  if forge == "gh" then
    return api.job_steps(root, forge, job.id, function(steps, err)
      job.busy = nil
      if steps then job.steps = steps end
      if err and not job.tail then job.tail = { err } end
      render()
    end)
  end
  api.job_log(root, forge, job.id, function(text, err)
    job.busy = nil
    if not text then
      job.tail = { err or "no log yet" }
      return render()
    end
    -- Strip the runner's ISO timestamp prefix and its markers; the pane has
    -- room for neither, and the full log is one <CR> away.
    local function clean(l) return vim.trim((l:gsub("^%d%d%d%d%-%d%d%-%d%dT[%d:%.]+Z ", ""):gsub("##%[%a+%]", ""))) end
    -- The literal last lines of a job are always its post-action cleanup -
    -- git config plumbing that says nothing about why the job failed. Cut
    -- there and the tail becomes the job's actual last output: the nix error
    -- on a failure, "all checks passed" on a success. (This is the runner's
    -- shape, which only Forgejo reaches - GitHub jobs expand as steps.)
    local pick = {}
    for _, raw in ipairs(vim.split(text, "\n", { plain = true })) do
      local l = clean(raw)
      if l:find("Run Post ", 1, true) then break end
      if l ~= "" then
        pick[#pick + 1] = l
        if #pick > TAIL then table.remove(pick, 1) end
      end
    end
    job.tail = pick
    render()
  end)
end

local function toggle()
  local job = job_at()
  if not job then return end
  local key = job.id or -1
  if expanded[key] then
    expanded[key] = nil
    return render()
  end
  if not job.id then return warn "this check has no job to expand" end
  expanded[key] = true
  fill(job)
  render()
end

--- <CR>: the log itself, in the window ABOVE the pane - the same "open the
--- real thing" that <CR> means on a file row in pr://files. q there comes
--- back, because it is a plain buffer switch.
local function enter()
  local job = job_at()
  if not job then return end
  if not job.id then
    if job.url then return vim.ui.open(job.url) end
    return warn "this check has no log"
  end
  local pane = pane_win()
  local target
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if w ~= pane then target = target or w end
  end
  if target then vim.api.nvim_set_current_win(target) end
  -- The sha travels with the job, because the log subscribes to the SAME
  -- store entry this pane does rather than polling the job on its own.
  require("pr.ci.log").open(root, sha, job)
end

local function web()
  local job = job_at()
  local url = job and job.url
  if not url then return warn "no URL for this check" end
  vim.ui.open(url)
end

---@param dir 1|-1
local function step(dir)
  local cur, best = vim.fn.line ".", nil
  for lnum in pairs(rows) do
    if dir == 1 and lnum > cur and (not best or lnum < best) then best = lnum end
    if dir == -1 and lnum < cur and (not best or lnum > best) then best = lnum end
  end
  if best then vim.api.nvim_win_set_cursor(0, { best, 0 }) end
end

local HELP = {
  { "g?", "this help" },
  { "<Tab> / =", "expand steps / log tail" },
  { "<CR>", "open the full log" },
  { "]j / [j", "next / prev job" },
  { "O", "open this check in the browser" },
  { "R / <c-r>", "refresh now" },
  { "q", "close the pane" },
}

-- ------------------------------------------------------------------- open ---

local function ensure_buf()
  if buf and vim.api.nvim_buf_is_valid(buf) then return end
  local cur = vim.api.nvim_get_current_buf()
  local adopt = vim.api.nvim_buf_get_name(cur):match "pr://checks$" ~= nil
  buf = adopt and cur or vim.api.nvim_create_buf(false, true)
  if not adopt then vim.api.nvim_buf_set_name(buf, "pr://checks") end
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "prchecks"
  vim.bo[buf].modifiable = false

  local o = { buffer = buf, silent = true }
  vim.keymap.set("n", "<Tab>", toggle, o)
  vim.keymap.set("n", "=", toggle, o)
  vim.keymap.set("n", "<CR>", enter, o)
  vim.keymap.set("n", "]j", function() step(1) end, o)
  vim.keymap.set("n", "[j", function() step(-1) end, o)
  vim.keymap.set("n", "O", web, o)
  vim.keymap.set("n", "q", function() M.close() end, o)
  require("pr.surface").refresh_keys(buf, function() M.refresh() end)
  vim.keymap.set("n", "g?", function() fmt.help(" pr checks ", HELP) end, o)
end

--- Subscribe to what the loaded review actually runs CI on. For a PR that is
--- its HEAD commit - the pane does NOT follow ]c / [c, because most commits
--- in a PR were never pushed on their own and have no checks of their own.
--- For a landed commit out of pr://log there is no PR: the commit IS the
--- thing CI ran on, so the pane keys on it directly - the same store entry
--- its orb in the log reads, upgraded to per-job detail by the watch.
---@return boolean ok
local function subscribe()
  local s = require("pr").state
  if not s.root then return false end
  local head
  if s.pr then
    head = data.resolve(s.root, data.ref(s.pr.number), true)
  else
    local c = s.commits[s.idx]
    head = c and (c.full or data.resolve(s.root, c.sha, true))
  end
  if not head or head == "" then return false end
  if unwatch and sha == head and root == s.root then return true end
  if unwatch then unwatch() end
  root, sha, entry = s.root, head, nil
  unwatch = ci.watch(root, sha, function(e)
    entry = e
    -- An expanded job re-reads its detail whenever the store updates, so the
    -- inline tail follows the log rather than freezing at open. The store
    -- hands back BRAND-NEW job tables every fetch, so a fresh row never
    -- carries the steps or tail its predecessor had - which is also why this
    -- cannot skip terminal jobs: the notify that flips a job to done is the
    -- one that would otherwise leave an open row showing "...".
    for _, job in ipairs(e.jobs or {}) do
      if expanded[job.id or -1] and not (job.steps or job.tail) then fill(job) end
    end
    render()
  end)
  return true
end

function M.open()
  if not subscribe() then return warn "nothing loaded - <c-p> first" end
  ensure_buf()
  local win = pane_win()
  if win then return vim.api.nvim_set_current_win(win) end
  ci.setup_hls()
  vim.cmd "botright split"
  vim.api.nvim_win_set_buf(0, buf)
  local w = 0
  vim.wo[w][0].winhighlight = ci.WINBAR
  vim.wo[w][0].winfixheight = true
  vim.wo[w][0].number = false
  vim.wo[w][0].relativenumber = false
  vim.wo[w][0].wrap = false
  vim.wo[w][0].cursorline = true
  vim.wo[w][0].signcolumn = "no"
  vim.wo[w][0].foldcolumn = "0"
  render()
end

function M.close()
  local win = pane_win()
  if unwatch then
    unwatch()
    unwatch = nil
  end
  if ticker then
    ticker:stop()
    if not ticker:is_closing() then ticker:close() end
    ticker = nil
  end
  entry, sha = nil, nil
  if win and #vim.api.nvim_tabpage_list_wins(0) > 1 then vim.api.nvim_win_close(win, true) end
end

function M.toggle()
  if M.is_open() then return M.close() end
  M.open()
end

function M.refresh()
  if root and sha then ci.refresh(root, sha) end
end

--- Re-point an open pane at whatever PR is loaded now. Called by pr.render,
--- so ]p / [p carry the pane along without it having to watch state itself.
function M.follow()
  if not M.is_open() then return end
  if subscribe() then render() end
end

return M
