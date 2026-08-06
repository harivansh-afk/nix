-- pr.threads.pane: pr://threads - the conversation of the loaded PR, one row
-- per item. The checks pane's sibling, structurally its clone: a bottom
-- split under pr://files, summary in the winbar, worst-first rows, <Tab> to
-- expand a row in place. T toggles it where G toggles checks.
--
-- Rows are the three item kinds the store speaks:
--   ● path:line       an unresolved code thread (the codex comment to answer)
--   ✗ / ✓ / ○ author  a verdict, or conversation chatter
--   ⊘                 resolved / outdated / dismissed, dim at the bottom
--
-- <Tab> expands the full thread - every reply, body wrapped. <CR> on a
-- thread jumps to the REAL file:line in the PR worktree (pr.tree, the same
-- materialisation <CR> on a file row uses), which is the entire point:
-- a review comment becomes the code it is about in one keystroke. On
-- anything without a file anchor, <CR> opens the forge's page for it.

local data = require "pr.data"
local fmt = require "pr.fmt"
local threads = require "pr.threads"

local M = {}

local ns = vim.api.nvim_create_namespace "pr_threads_pane"

local buf ---@type integer?
local unwatch ---@type fun()?
local number, root ---@type integer?, string?
local entry ---@type pr.threads.Entry?
local expanded = {} ---@type table<string, true>
local rows = {} ---@type table<integer, table> lnum -> item
local vt = {} ---@type table<integer, integer> lnum -> virt-text extmark id

local MAX_HEIGHT = 15

local function warn(msg) vim.notify("pr: " .. msg, vim.log.levels.WARN) end

---@return integer? win
local function pane_win()
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then return nil end
  local w = vim.fn.bufwinid(buf)
  return w ~= -1 and w or nil
end

function M.is_open() return pane_win() ~= nil end

--- Every item's identity across renders, for the expanded set.
local function ikey(item) return item.kind == "thread" and item.key or (item.kind .. (item.id or "?")) end

-- ----------------------------------------------------------------- winbar ---

local function paint(hl, text) return ("%%#%s#%s%%*"):format(hl, text) end

--- "2 unresolved, 1 changes, 3 comments, 1 approved" - actionable first,
--- empty classes omitted, settled counted but never shouted.
local function summary(e)
  if #e.items == 0 then return paint("Comment", "no conversation") end
  local c = e.counts
  local parts = {}
  local function add(n, word, hl)
    if (n or 0) > 0 then parts[#parts + 1] = paint(hl, ("%d %s"):format(n, word)) end
  end
  add(c.thread, "unresolved", threads.HL.thread)
  add(c.changes, "changes", threads.HL.changes)
  add((c.comment or 0) + (c.commented or 0), "comments", "Comment")
  add(c.approved, "approved", threads.HL.approved)
  add(c.settled, "settled", "Comment")
  return table.concat(parts, paint("Comment", ", "))
end

local function winbar()
  local win = pane_win()
  if not win then return end
  local bits = {}
  if number then bits[#bits + 1] = paint("fugitiveCount", "#" .. number) end
  if entry then
    if entry.state == "error" then
      bits[#bits + 1] = paint("DiagnosticError", "error")
    elseif entry.state == "loading" then
      bits[#bits + 1] = paint("Comment", "loading")
    else
      bits[#bits + 1] = summary(entry)
    end
  end
  vim.wo[win][0].winbar = " " .. table.concat(bits, paint("Comment", " · "))
end

-- ----------------------------------------------------------------- render ---

--- Greedy word-wrap of a markdown body into indented display lines. Fenced
--- code keeps its own lines (wrapping code lies about it) and renders dim;
--- prose fills the pane's width.
---@return {[1]:string,[2]:string?}[] lines  text, hl
local function body_lines(body, width)
  local out, fenced = {}, false
  for _, raw in ipairs(vim.split(body or "", "\n", { plain = true })) do
    local line = raw:gsub("\r$", "")
    if line:match "^%s*```" then
      fenced = not fenced
    elseif fenced then
      out[#out + 1] = { line, "Comment" }
    elseif vim.trim(line) == "" then
      if #out > 0 and out[#out][1] ~= "" then out[#out + 1] = { "" } end
    else
      local cur
      for _, w in ipairs(vim.split(vim.trim(line), "%s+")) do
        if not cur then
          cur = w
        elseif vim.fn.strdisplaywidth(cur .. " " .. w) > width then
          out[#out + 1] = { cur }
          cur = w
        else
          cur = cur .. " " .. w
        end
      end
      if cur then out[#out + 1] = { cur } end
    end
  end
  while #out > 0 and out[#out][1] == "" do
    table.remove(out)
  end
  return out
end

--- The one-line label a collapsed row wears.
---@return {[1]:string,[2]:string?}[] segs
local function label(item)
  local sym, hl = threads.SYM[item.face], threads.HL[item.face]
  local segs = { { " " }, { sym, hl }, { " " } }
  if item.kind == "thread" then
    segs[#segs + 1] = { (item.path or "?") .. (item.line and (":" .. item.line) or ""), "Directory" }
    local last = item.comments[#item.comments]
    segs[#segs + 1] = { "  " }
    segs[#segs + 1] = { last and last.author or "?", "Identifier" }
    if item.outdated then segs[#segs + 1] = { " (outdated)", "Comment" } end
  elseif item.kind == "review" then
    local verb = item.verdict == "approved" and "approved"
      or item.verdict == "changes" and "requested changes"
      or "commented"
    if item.dismissed then verb = verb .. " (dismissed)" end
    segs[#segs + 1] = { item.author, "Identifier" }
    segs[#segs + 1] = { " " .. verb, item.dismissed and "Comment" or nil }
    local first = vim.split(item.body or "", "\n", { plain = true })[1]
    if vim.trim(first or "") ~= "" then segs[#segs + 1] = { "  " .. first, "Comment" } end
  else
    segs[#segs + 1] = { item.author, "Identifier" }
    local first = vim.split(item.body or "", "\n", { plain = true })[1]
    if vim.trim(first or "") ~= "" then segs[#segs + 1] = { "  " .. first, "Comment" } end
  end
  return segs
end

--- The right-aligned meta: reply count for threads, then age.
local function meta(item)
  local out = {}
  if item.kind == "thread" and #item.comments > 1 then
    out[#out + 1] = { ("(%d)"):format(#item.comments), "Comment" }
    out[#out + 1] = { "  " }
  end
  out[#out + 1] = { fmt.since(item.ts), "Comment" }
  out[#out + 1] = { " " }
  return out
end

local function set_meta(lnum, item)
  vt[lnum] = vim.api.nvim_buf_set_extmark(buf, ns, lnum - 1, 0, {
    id = vt[lnum],
    virt_text = meta(item),
    virt_text_pos = "right_align",
  })
end

--- Detail lines under an expanded item: every comment as "author · age"
--- then its wrapped body - one comment for chatter, the whole chain for a
--- thread. Wrapped HERE, not at fetch, so a resized window re-cuts.
local function detail(item, width)
  local out = {}
  local comments = item.kind == "thread" and item.comments
    or { { author = item.author, body = item.body, ts = item.ts } }
  for _, c in ipairs(comments) do
    out[#out + 1] = { ("    %s · %s"):format(c.author or "?", fmt.since(c.ts)), "Identifier" }
    for _, l in ipairs(body_lines(c.body, width - 8)) do
      out[#out + 1] = { l[1] == "" and "" or ("      " .. l[1]), l[2] }
    end
  end
  if #out == 0 then out[1] = { "    (empty)", "Comment" } end
  return out
end

local function render()
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then return end
  local lines, marks = {}, {}
  rows, vt = {}, {}
  local seg = fmt.segmenter(lines, marks, function(row, group, from, to) return { row, from, to, group } end)

  local win = pane_win()
  local width = (win and vim.api.nvim_win_get_width(win) or vim.o.columns) - 2

  local e = entry
  if not e or e.state == "loading" then
    lines[1] = " loading conversation..."
  elseif e.state == "error" then
    seg { { " ! ", "DiagnosticError" }, { e.err or "could not read the conversation" } }
  elseif #e.items == 0 then
    lines[1] = " nothing said on #" .. (number or "?")
  else
    for _, item in ipairs(e.items) do
      seg(label(item))
      rows[#lines] = item
      if expanded[ikey(item)] then
        for _, d in ipairs(detail(item, width)) do
          lines[#lines + 1] = d[1]
          if d[2] then marks[#marks + 1] = { #lines - 1, 0, -1, d[2] } end
        end
      end
    end
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false -- a render is a load, never an edit

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, m in ipairs(marks) do
    local to = m[3] == -1 and #lines[m[1] + 1] or m[3]
    vim.api.nvim_buf_set_extmark(buf, ns, m[1], m[2], { end_col = to, hl_group = m[4] })
  end
  for lnum, item in pairs(rows) do
    set_meta(lnum, item)
  end

  if win then vim.api.nvim_win_set_height(win, math.max(1, math.min(#lines, MAX_HEIGHT))) end
  winbar()
end

-- ---------------------------------------------------------------- actions ---

local function item_at() return rows[vim.fn.line "."] end

local function toggle_row()
  local item = item_at()
  if not item then return end
  local key = ikey(item)
  expanded[key] = not expanded[key] or nil
  render()
end

--- <CR>: the real thing. A thread's real thing is the code it is about -
--- pr.tree materialises the PR and the file opens at the commented line in
--- the window ABOVE the pane, exactly like <CR> on a file row. Everything
--- else's real thing is its page on the forge.
local function enter()
  local item = item_at()
  if not item then return end
  if item.kind ~= "thread" or not item.path then
    if item.url then return vim.ui.open(item.url) end
    return warn "nothing to open for this row"
  end
  local pane = pane_win()
  local target
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if w ~= pane then target = target or w end
  end
  if target then vim.api.nvim_set_current_win(target) end
  require("pr.tree").open(item.path, item.line)
end

local function web()
  local item = item_at()
  local url = item and item.url
  if not url then return warn "no URL for this row" end
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
  { "<Tab> / =", "expand the thread / body" },
  { "<CR>", "jump to the code (threads) / open the page" },
  { "]t / [t", "next / prev item" },
  { "O", "open this item in the browser" },
  { "R / <c-r>", "refresh now" },
  { "q", "close the pane" },
}

-- ------------------------------------------------------------------- open ---

local function ensure_buf()
  if buf and vim.api.nvim_buf_is_valid(buf) then return end
  local cur = vim.api.nvim_get_current_buf()
  local adopt = vim.api.nvim_buf_get_name(cur):match "pr://threads$" ~= nil
  buf = adopt and cur or vim.api.nvim_create_buf(false, true)
  if not adopt then vim.api.nvim_buf_set_name(buf, "pr://threads") end
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "prthreads"
  vim.bo[buf].modifiable = false

  local o = { buffer = buf, silent = true }
  vim.keymap.set("n", "<Tab>", toggle_row, o)
  vim.keymap.set("n", "=", toggle_row, o)
  vim.keymap.set("n", "<CR>", enter, o)
  vim.keymap.set("n", "]t", function() step(1) end, o)
  vim.keymap.set("n", "[t", function() step(-1) end, o)
  vim.keymap.set("n", "O", web, o)
  vim.keymap.set("n", "q", function() M.close() end, o)
  require("pr.surface").refresh_keys(buf, function() M.refresh() end)
  vim.keymap.set("n", "g?", function() fmt.help(" pr threads ", HELP) end, o)
end

--- Subscribe to the loaded PR's conversation. A landed commit out of
--- pr://log has no PR and therefore no conversation - that is a warn, not a
--- fallback.
---@return boolean ok
local function subscribe()
  local s = require("pr").state
  if not (s.root and s.pr) then return false end
  if unwatch and number == s.pr.number and root == s.root then return true end
  if unwatch then unwatch() end
  root, number, entry = s.root, s.pr.number, nil
  unwatch = threads.watch(root, number, function(e)
    entry = e
    render()
  end)
  return true
end

function M.open()
  if not subscribe() then return warn "no PR loaded - <c-p> first (a bare commit has no conversation)" end
  ensure_buf()
  local win = pane_win()
  if win then return vim.api.nvim_set_current_win(win) end
  require("pr.ci").setup_hls()
  vim.cmd "botright split"
  vim.api.nvim_win_set_buf(0, buf)
  local w = 0
  vim.wo[w][0].winhighlight = require("pr.ci").WINBAR
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
  entry, number = nil, nil
  if win and #vim.api.nvim_tabpage_list_wins(0) > 1 then vim.api.nvim_win_close(win, true) end
end

function M.toggle()
  if M.is_open() then return M.close() end
  M.open()
end

function M.refresh()
  if root and number then threads.refresh(root, number) end
end

--- Re-point an open pane at whatever PR is loaded now. Called by pr.render,
--- so ]p / [p carry it along - the same ride the checks pane gets.
function M.follow()
  if not M.is_open() then return end
  if subscribe() then return render() end
  M.close() -- a landed commit has no conversation; a stale pane would lie
end

return M
