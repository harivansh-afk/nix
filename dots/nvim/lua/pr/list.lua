-- pr.list: the PR home surface - one buffer (pr://list), one line per PR.
--
-- Stacks are detected from branch topology alone: a PR whose base branch is
-- another open PR's head branch is that PR's child, and renders indented
-- under it. The flat display order is exported as M.order, and ]p / [p in
-- the files view walk exactly that order - so reviewing a stack is just
-- stepping through adjacent lines.
--
-- Canola-style: the buffer IS the list. <CR> dives into a PR (pr://files),
-- "-" in the files view comes back up here. A PR on the fast list (pr.marks)
-- wears its slot digit in the column immediately left of its title.
--
-- F flips the mine-filter: only PRs I authored. Durable (a state file, so it
-- survives sessions) and render-time (cuts the cached fetch, never refetches).

local data = require "pr.data"
local fmt = require "pr.fmt"
local surface = require "pr.surface"

local M = {}

M.order = {} ---@type table[] PRs in display order (stacks adjacent, parent first)
M.root = nil ---@type string?

--- Declared before `render`, which closes over it, and built at the bottom of
--- the file, where `render` exists to hand it. Lua has no forward reference
--- for one half of a mutual pair, so one of them has to be an upvalue.
local S ---@type pr.Surface

local function warn(msg) vim.notify("pr: " .. msg, vim.log.levels.WARN) end

-- ------------------------------------------------------------------- mine ---

--- The mine-filter (F): show only PRs I authored. Durable across sessions -
--- the whole setting is the existence of one empty file under stdpath state,
--- so there is no config format to parse and nothing to migrate.
local MINE = vim.fn.stdpath "state" .. "/pr-mine"

local mine = (vim.uv or vim.loop).fs_stat(MINE) ~= nil

--- My forge login, resolved once per session (pr.data.me caches by host).
--- `false` = lookup failed; while nil (in flight) the filter stays inactive
--- and the list renders unfiltered rather than empty.
local me ---@type string|false|nil

--- Is the filter actually filtering right now?
local function filtering() return mine and type(me) == "string" end

---@param prs table[]
---@return table[]
local function visible(prs)
  if not filtering() then return prs end
  return vim.tbl_filter(function(p) return p.author and p.author.login == me end, prs)
end

--- Resolve `me` if the filter needs it, then repaint: the list may already be
--- on screen unfiltered when the login lands.
local function resolve_me()
  if not (mine and me == nil and M.root) then return end
  data.me(M.root, function(login)
    me = login or false
    if not login then warn "could not resolve your forge login - showing all PRs" end
    M.repaint()
  end)
end

-- ------------------------------------------------------------------ stack ---

--- Order PRs so stack members are adjacent, parent first, children indented.
--- Detection: base branch == another open PR's head branch => child.
---@param prs table[]
---@return table[] order each entry gains a `depth` field (0 = root)
local function stacked(prs)
  local by_head, children, roots = {}, {}, {}
  for _, p in ipairs(prs) do
    if p.headRefName and p.headRefName ~= "" then by_head[p.headRefName] = p end
  end
  for _, p in ipairs(prs) do
    local parent = p.baseRefName and by_head[p.baseRefName]
    if parent and parent.number ~= p.number then
      children[parent.number] = children[parent.number] or {}
      table.insert(children[parent.number], p)
    else
      roots[#roots + 1] = p
    end
  end
  local order, seen = {}, {}
  local function walk(p, depth)
    if seen[p.number] then return end
    seen[p.number] = true
    p.depth = depth
    order[#order + 1] = p
    for _, c in ipairs(children[p.number] or {}) do
      walk(c, depth + 1)
    end
  end
  for _, p in ipairs(roots) do
    walk(p, 0)
  end
  -- Base cycles (a based on b, b based on a) leave no root: append flat.
  for _, p in ipairs(prs) do
    walk(p, 0)
  end
  return order
end

-- ----------------------------------------------------------------- render ---

--- Last rendered PR set, so resize re-renders re-flow the columns.
local last ---@type table[]?

local function render(prs)
  if not prs then return end
  last = prs
  -- The filter cuts at render time, off the LAST FETCH: toggling never costs
  -- a network call, and F back restores everyone's PRs instantly. A filtered
  -- parent simply promotes its children to roots in `stacked`.
  M.order = stacked(visible(prs))

  -- fzf-picker-era columns: number | title (fills the window) | author | age,
  -- author + age right-aligned against the window edge. Title absorbs
  -- whatever the fixed columns leave, truncating into "…" when narrow.
  -- 3 = leading space + orb + space, 6 = the number column, 2 = the fast-list
  -- slot; display cells.
  local title_w = surface.title_width(S:width(), 3 + 6 + 2)

  -- The fast list, as a digit immediately left of the title. Its two cells
  -- are charged to title_w above and spent on every row, blank or not, so
  -- titles stay in one column and marking a PR re-flows nothing. Past slot 9
  -- the digit would not fit in one cell, so it degrades to "+": a tenth mark
  -- is a fast list that is no longer fast, and <leader>N only reaches nine.
  local slots = require("pr.marks").slots(M.root)

  local lines, marks = {}, {}
  local seg = surface.segmenter(lines, marks)

  for _, p in ipairs(M.order) do
    local glyph, hl = surface.orb(p.ci)
    local slot = slots[p.number]
    local connector = p.depth > 0 and (string.rep("  ", p.depth - 1) .. "└ ") or ""
    local title = fmt.trunc(connector .. (p.title or ""), title_w)
    seg {
      { " " },
      { glyph, hl },
      { " " },
      { ("#%-5d"):format(p.number), p.isDraft and "Comment" or "DiagnosticOk" }, -- grey = draft
      { "  " },
      slot and { slot < 10 and tostring(slot) or "+", "Constant" } or { " " },
      { " " },
      { connector, "Constant" }, -- └ in purple (CozyboxPurple)
      { title:sub(#connector + 1) },
      { string.rep(" ", math.max(0, title_w - vim.fn.strdisplaywidth(title))) },
      { "  " },
      { fmt.rjust(p.author and p.author.login or "?", surface.AUTHOR_W), "Identifier" },
      { "  " },
      { fmt.rjust(fmt.ago(p.updatedAt), surface.AGE_W), "Comment" },
    }
  end
  -- No footer indicator while filtering - user preference: the buffer stays
  -- rows only. The empty-list message is the one place the filter names
  -- itself, so an all-yours-merged morning is not mistaken for no PRs at all.
  if #lines == 0 then seg { { filtering() and (" no open PRs by " .. me) or " no open PRs" } } end

  S:paint(lines, marks)
end

--- Re-paint the last fetched set with no network call. The verbs mutate PR
--- tables in place (draft flips a highlight, nothing else), so this is all
--- the redraw they need.
function M.repaint()
  if last and S:valid() then render(last) end
end

--- Force the next M.open to re-fetch, without touching the buffer now.
function M.invalidate() M.order = {} end

--- Stack membership for a PR number, read straight off the display order
--- (a stack = a depth-0 root plus the depth>0 run under it). Feeds the
--- files-view "Stack: 2/3" counter as ]p / [p walk the list.
---@param number integer
---@return {pos:integer, total:integer, parent:table?}? nil when not in a stack
function M.stack_info(number)
  local i0
  for i, p in ipairs(M.order) do
    if p.number == number then
      i0 = i
      break
    end
  end
  if not i0 then return end
  local root = i0
  while M.order[root].depth > 0 do
    root = root - 1
  end
  local last = root
  while M.order[last + 1] and M.order[last + 1].depth > 0 do
    last = last + 1
  end
  if last == root then return end -- not stacked
  local me, parent = M.order[i0], nil
  for i = i0 - 1, root, -1 do
    if M.order[i].depth == me.depth - 1 then
      parent = M.order[i]
      break
    end
  end
  return { pos = i0 - root + 1, total = last - root + 1, parent = me.depth > 0 and parent or nil }
end

--- Land the cursor on the currently loaded PR, if it is in the list.
local function focus_current()
  local cur = require("pr").state.pr
  if not cur then return end
  for i, p in ipairs(M.order) do
    if p.number == cur.number then return pcall(vim.api.nvim_win_set_cursor, 0, { i, 0 }) end
  end
end

-- ------------------------------------------------------------------- help ---

-- ------------------------------------------------------------------- open ---

local function select()
  local p = M.order[vim.fn.line "."]
  if p and M.root then require("pr").load(M.root, p) end
end

--- F: flip the mine-filter and persist it (create or remove the state file),
--- then repaint from the cached fetch - no network either way.
local function toggle_mine()
  mine = not mine
  if mine then
    local f = io.open(MINE, "w")
    if f then f:close() end
  else
    os.remove(MINE)
  end
  resolve_me()
  vim.notify("pr: " .. (mine and "only your PRs" or "everyone's PRs"), vim.log.levels.INFO)
  M.repaint()
end

--- Buffer identity, options, the resize re-render, the paint and the
--- generation guard are all pr.surface's; this supplies the rows and the keys.
S = surface.new {
  name = "pr://list",
  filetype = "prlist",
  title = " pr list ",
  help = {
    { "g?", "this help" },
    { "<CR>", "review PR (pr://files)" },
    { "L", "commit log (pr://log)" },
    { "F", "only my PRs <-> everyone's (durable)" },
    { "]p / [p", "next / prev PR (global)" },
    { "R / <c-r>", "refresh" },
    { "q", "back" },
  },
  render = function()
    if last then render(last) end
  end,
  refresh = function() M.open(true) end,
  keys = function(b)
    local o = { buffer = b, silent = true }
    vim.keymap.set("n", "<CR>", select, o)
    vim.keymap.set("n", "L", function() require("pr.log").open() end, o)
    vim.keymap.set("n", "F", toggle_mine, { buffer = b, silent = true, desc = "pr: only my PRs <-> everyone's" })
  end,
}

--- Light the orbs from the CI store, one PR at a time as answers land.
---
--- A PR's CI is the CI of its HEAD COMMIT, so the orb is the rollup of that
--- sha's store entry - the exact entry the pane renders in detail, which is
--- what makes it impossible for this orb and an open pane to disagree. Head
--- shas come from the local origin/pr/* refs in one git call (data.pr_heads);
--- a PR opened since the last fetch has no ref yet, so ONE background fetch
--- heals the stragglers and primes just them.
---@param prs table[]
---@param gen integer
---@param force? boolean
local function light_orbs(root, prs, gen, force)
  local ci = require "pr.ci"

  local function prime(list)
    local shas, by_sha = {}, {}
    for _, p in ipairs(list) do
      if p.head_sha then
        shas[#shas + 1] = p.head_sha
        by_sha[p.head_sha] = p
      end
    end
    ci.prime(root, shas, function(sha, entry)
      if not S:current(gen) then return end
      local p = by_sha[sha]
      if p and p.ci ~= entry.rollup then
        p.ci = entry.rollup
        -- Re-render in place: the line count is unchanged, so the cursor
        -- stays put; one repaint per landing is what "incremental" means.
        render(prs)
      end
    end, { force = force })
  end

  local heads = data.pr_heads(root)
  local missing = false
  for _, p in ipairs(prs) do
    p.head_sha = heads[p.number]
    missing = missing or not p.head_sha
  end
  prime(prs)

  if not missing then return end
  data.fetch(root, function(ok)
    if not (ok and S:current(gen)) then return end
    local healed, again = data.pr_heads(root), {}
    for _, p in ipairs(prs) do
      if not p.head_sha and healed[p.number] then
        p.head_sha = healed[p.number]
        again[#again + 1] = p
      end
    end
    prime(again)
  end)
end

--- Open the list; the buffer caches the last fetch (guh-style: load eagerly,
--- refetch only on explicit refresh). First open and R fetch.
---
--- Two-phase load: the fast metadata list renders immediately, then the CI
--- states trail in from the store and recolor the orbs row by row.
---@param refresh? boolean
function M.open(refresh)
  local root = data.root()
  if not root then return warn "not in a git repository" end
  if not data.has_refspec(root) then
    if not data.install_refspec(root) then return warn "could not write git config" end
  end

  S:ensure()
  S:show()

  if #M.order > 0 and M.root == root and not refresh then return focus_current() end

  M.root = root
  resolve_me() -- the durable filter may be on before `me` is known
  local gen = S:bump()
  S:placeholder "loading PRs..."

  data.prs(root, function(prs, err)
    if not S:current(gen) then return end
    if not prs then return warn(err or "could not list PRs") end
    render(prs)
    if vim.api.nvim_get_current_buf() == S.buf then focus_current() end
    light_orbs(root, prs, gen, refresh)
  end)
end

return M
