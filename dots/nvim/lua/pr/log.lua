-- pr.log: the commit log surface - one buffer (pr://log), one line per commit.
--
-- pr://list is the forge's open work; this is the branch's landed work. Same
-- object (pr.surface), same columns, same orbs, same two-phase load - the
-- only difference is that a row is a commit rather than a PR, so the left
-- column is a sha and there is no stacking.
--
-- <CR> opens the commit on pr://files, which means every gesture already
-- built for reviewing a PR works on a landed commit too: <Tab> for inline
-- hunks, dd/dv for the full diffs.nvim review, and <CR> on a file row for the
-- real file at that commit via pr.tree.
--
-- Not to be confused with pr.ci.log, which is one CI job's output. This is
-- `git log`; that is a job log.
--
-- The log is of HEAD, so this buffer and `git log` in a terminal are the
-- same list in the same order, always - an earlier draft showed origin/main
-- and read as "wrong commits" the moment local main was ahead. Commits that
-- exist only locally have no CI and wear the hollow orb, which is the truth.
--
-- Orbs come from the pr.ci store via prime: one truthful request per sha
-- (the runs API, never the combined status - see pr.ci.api), bounded and
-- incremental, and the same store entry the pane renders when G dives in.

local data = require "pr.data"
local fmt = require "pr.fmt"
local surface = require "pr.surface"

local M = {}

local function warn(msg) vim.notify("pr: " .. msg, vim.log.levels.WARN) end
local function info(msg) vim.notify("pr: " .. msg, vim.log.levels.INFO) end

--- One PAGE of history, not a ceiling. The log opens at a depth that covers
--- "what landed lately", because every row costs one CI request and priming
--- five hundred ancient commits' orbs is pure waste - and grows by another
--- page each `+`, priming only the new rows (older entries usually answer
--- from the store anyway).
local PAGE = 50

M.commits = {} ---@type table[] rows in display order, newest first
M.root = nil ---@type string?
M.ref = nil ---@type string?
local depth = PAGE

--- Declared before `render`, built at the bottom - see the note in pr.list.
local S ---@type pr.Surface

-- ----------------------------------------------------------------- render ---

local function render()
  if not S:valid() then return end

  -- Same fzf-picker-era split as pr://list: sha | subject (fills) | author |
  -- age, with author and age right-aligned against the window edge.
  -- 3 = leading space + orb + space, 8 = the sha column; display cells.
  local sha_w = 8
  local subject_w = surface.title_width(S:width(), 3 + sha_w)

  local lines, marks = {}, {}
  local seg = surface.segmenter(lines, marks)

  for _, c in ipairs(M.commits) do
    local glyph, hl = surface.orb(c.ci)
    local subject = fmt.trunc(c.subject or "", subject_w)
    seg {
      { " " },
      { glyph, hl },
      { " " },
      -- fugitiveHash is the same group the pr://files header paints a sha in.
      { fmt.ljust(c.sha, sha_w), "fugitiveHash" },
      { " " },
      { subject },
      { string.rep(" ", math.max(0, subject_w - vim.fn.strdisplaywidth(subject))) },
      { "  " },
      { fmt.rjust(c.author or "?", surface.AUTHOR_W), "Identifier" },
      { "  " },
      { fmt.rjust(fmt.since(c.ts), surface.AGE_W), "Comment" },
    }
  end
  if #lines == 0 then lines = { " no commits" } end

  S:paint(lines, marks)
end

-- ---------------------------------------------------------------- actions ---

---@return table? commit
local function under_cursor() return M.commits[vim.fn.line "."] end

--- Review the commit under the cursor on pr://files. "Incremental" is what a
--- landed commit means - what THIS commit changed, sha^..sha - so the range
--- is the one `]c` already produces inside a PR, and every key on that
--- surface behaves identically.
local function select()
  local c = under_cursor()
  if not (c and M.root) then return end
  require("pr").load_commit(M.root, c)
end

--- The full diffs.nvim review of just this commit, without going via
--- pr://files. `dd`/`dv` here mean what they mean there.
local function dive()
  local c = under_cursor()
  if not (c and M.root) then return end
  local ok, commands = pcall(require, "diffs.commands")
  if not ok then return warn "diffs.nvim is not available" end
  commands.review(data.spec(M.root, c.sha .. "^", c.sha, "incremental"))
end

--- G: the checks pane for the commit under the cursor - the same key it is
--- on pr://files, and the same store entry this row's orb was painted from,
--- upgraded to per-job detail by the pane's watch. Loading the commit first
--- is what makes the pane's "follow the review" contract hold.
local function checks()
  local c = under_cursor()
  if not (c and M.root) then return end
  require("pr").load_commit(M.root, c)
  require("pr.ci.pane").open()
end

--- Open the commit in the forge's web UI. Both forges spell a commit page
--- /commit/<sha> under the repo, so pr.data.web_url's PR path is not reusable.
local function web()
  local c = under_cursor()
  if not (c and M.root) then return end
  local url = data.commit_url(M.root, c.sha)
  if not url then return warn "could not derive a URL from origin" end
  pcall(vim.ui.open, url)
end

-- ------------------------------------------------------------------- open ---

S = surface.new {
  name = "pr://log",
  filetype = "prlog",
  title = " pr log ",
  help = {
    { "g?", "this help" },
    { "<CR>", "review commit (pr://files)" },
    { "dd / dv", "full review of this commit" },
    { "G", "CI checks pane for this commit" },
    { "O", "open commit in browser" },
    { "+", "50 more commits" },
    { "-", "PR list" },
    { "R / <c-r>", "pull + refresh" },
    { "q", "back" },
  },
  render = render,
  refresh = function() M.open(nil, true) end,
  keys = function(b)
    local o = { buffer = b, silent = true }
    vim.keymap.set("n", "<CR>", select, o)
    vim.keymap.set("n", "dd", dive, o)
    vim.keymap.set("n", "dv", dive, o)
    vim.keymap.set("n", "G", checks, o)
    vim.keymap.set("n", "O", web, o)
    vim.keymap.set("n", "+", function() M.more() end, o)
    vim.keymap.set("n", "-", function() require("pr.list").open() end, o)
  end,
}

--- Light the orbs for `commits` from the store. Each landing repaints, which
--- is cheap (the line count never changes, so the cursor holds) and means
--- the log fills in progressively rather than waiting on the slowest answer.
---@param commits table[]  the rows to prime - a page, never the whole log
---@param gen integer
---@param force? boolean
local function light_orbs(root, commits, gen, force)
  local shas, by_sha = {}, {}
  for _, c in ipairs(commits) do
    shas[#shas + 1] = c.full
    by_sha[c.full] = c
  end
  require("pr.ci").prime(root, shas, function(sha, entry)
    if not S:current(gen) then return end
    local c = by_sha[sha]
    if c and c.ci ~= entry.rollup then
      c.ci = entry.rollup
      render()
    end
  end, { force = force })
end

--- Load the log to the current depth and render. The one loader open and
--- `+` share; `only` narrows the CI priming to rows that are actually new.
---@param force? boolean  re-ask the forge even for cached entries (R)
local function load(force)
  local gen = S:bump()
  local commits = data.log(M.root, M.ref, depth)
  if #commits == 0 then return S:placeholder("no commits on " .. M.ref) end
  local grew = #commits > #M.commits
  local from = #M.commits
  M.commits = commits
  render()
  -- On R everything re-primes; on + only the page that just appeared pays
  -- (the earlier rows' entries are already in the store and answer free).
  light_orbs(M.root, force and commits or vim.list_slice(commits, from + 1), gen, force)
  return grew
end

--- +: another page of history. The log opens shallow because every row costs
--- one CI request; depth is bought a page at a time, and sticks until the
--- log is pointed somewhere else.
local function more()
  if not M.root then return end
  depth = depth + PAGE
  if not load(false) then
    depth = #M.commits -- the ref ran out: do not creep past reality
    warn("no commits past " .. #M.commits .. " on " .. M.ref)
  end
end

--- R / :e - re-read from ORIGIN, not just re-ask CI. `:e` on a real file
--- rereads it from disk; the log's disk is the forge, and the log is of
--- HEAD, so fresh forge state (the PR just merged in the browser) appears
--- only once HEAD moves: a fast-forward pull on a branch, a plain fetch when
--- detached (there is no branch to move). Renders what it has FIRST and
--- pulls behind it - the buffer must never sit blank while the network
--- answers - then re-reads at the depth + has bought, CI re-asked too.
local function reload()
  render()
  local function done(verb)
    return function(ok, err)
      if not ok then warn(verb .. " failed: " .. (err or "")) end
      -- Even a failed pull usually completed its fetch half; re-read either
      -- way so the buffer reflects whatever DID change.
      load(true)
      if ok and verb == "pull" then
        -- HEAD moved under every open buffer; reread the unmodified ones and
        -- let fugitive surfaces notice, exactly as pr.tree does after a move.
        pcall(vim.cmd, "silent! checktime")
        pcall(vim.cmd, "silent! doautocmd User FugitiveChanged")
      end
    end
  end
  local h = data.head(M.root)
  if h.branch then
    info("pulling " .. h.branch .. "...")
    data.pull(M.root, done "pull")
  else
    info "detached HEAD - fetching origin..."
    data.fetch(M.root, done "fetch")
  end
end

--- Open the commit log. Cached like pr://list: the first open and R fetch,
--- anything else re-shows what is already there.
---
--- Two-phase, for the same reason pr://list is: `git log` is local and
--- instant, so the rows are on screen before any forge call is made, and the
--- orbs fill in behind them row by row as the store primes.
---@param ref? string  defaults to HEAD - this buffer must equal `git log`
---@param refresh? boolean
function M.open(ref, refresh)
  local root = data.root()
  if not root then return warn "not in a git repository" end
  ref = ref or M.ref or "HEAD"

  S:ensure()
  S:show()

  if #M.commits > 0 and M.root == root and M.ref == ref then
    -- Warm buffer: plain open just shows it, R / :e goes back to origin.
    if refresh then reload() end
    return
  end

  -- A new target starts shallow again; R keeps whatever depth + has bought.
  if M.root ~= root or M.ref ~= ref then depth = PAGE end
  M.root, M.ref = root, ref
  M.commits = {}
  load(refresh)
end

M.more = more

return M
