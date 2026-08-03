-- pr.marks: the fast list - the few PRs you are actually working through
-- right now, in an order you chose.
--
-- Harpoon's idea without harpoon's menu. A mark is a PR NUMBER and nothing
-- else: every other field of a PR (title, base branch, draft state) lives on
-- the forge and changes without asking, so a stored copy is a stale row
-- waiting to load the wrong diff. The number resolves through pr.list.order
-- at jump time, and one forge call settles the case where the list has not
-- been opened yet in this session.
--
-- Slots are positional and stable: slot 2 stays slot 2 until you unmark it,
-- so <leader>2 is muscle memory rather than a guess. The slot digit renders
-- in its own two-cell column immediately left of the title on pr://list,
-- spent on every row whether marked or not, so no column re-flows.
--
-- Marks are per repository and outlive the session (one JSON file under
-- stdpath("state")), written on every change: a mark costs one keypress and
-- must not be lost to a crash that VimLeavePre never sees.

local data = require "pr.data"

local M = {}

local FILE = vim.fs.joinpath(vim.fn.stdpath "state", "pr-marks.json")

local store ---@type table<string, integer[]>? repo root -> PR numbers, lazy-read

local function warn(msg) vim.notify("pr: " .. msg, vim.log.levels.WARN) end

-- ------------------------------------------------------------------ store ---

---@return table<string, integer[]>
local function load()
  if store then return store end
  store = {}
  if vim.fn.filereadable(FILE) == 1 then
    local ok, decoded = pcall(vim.json.decode, table.concat(vim.fn.readfile(FILE), "\n"))
    if ok and type(decoded) == "table" then store = decoded end
  end
  return store
end

--- Replace one repo's marks and make that fact visible everywhere at once.
--- An empty list drops its key rather than persisting `[]` forever.
---@param root string
---@param numbers integer[]
local function set(root, numbers)
  load()[root] = #numbers > 0 and numbers or nil
  vim.fn.mkdir(vim.fs.dirname(FILE), "p")
  pcall(vim.fn.writefile, { vim.json.encode(store) }, FILE)
  require("pr").repaint()
end

--- The repo the marks belong to: whatever the flow is pointed at, and only
--- the cwd's repo when nothing is loaded. A file opened out of a PR worktree
--- (pr.tree) is its own git root, and marking from one must not start a
--- second list keyed on a directory that gets cleaned away.
---@return string?
function M.root()
  local s = require("pr").state
  if s.root then return s.root end
  local list = package.loaded["pr.list"]
  return (list and list.root) or data.root()
end

---@param root string
---@return integer[]
function M.numbers(root) return load()[root] or {} end

--- Is there anything to step through? The ]m fallback asks this on every
--- press, so unlike M.root it never shells out for a repo root: with no flow
--- loaded there is nothing to step to, and the key stays vim's own.
---@return boolean
function M.any()
  local list = package.loaded["pr.list"]
  local root = require("pr").state.root or (list and list.root)
  return root ~= nil and #M.numbers(root) > 0
end

--- number -> slot, built once per paint rather than scanned per row.
---@param root string?
---@return table<integer, integer>
function M.slots(root)
  local out = {}
  for i, number in ipairs(M.numbers(root)) do
    out[number] = i
  end
  return out
end

-- ----------------------------------------------------------------- verbs ---

--- A fresh list with one number gone, and whether it was there at all. Both
--- ways of removing a mark are this plus what to do about `held`.
---@param numbers integer[]
---@param number integer
---@return integer[], boolean held
local function without(numbers, number)
  local out, held = {}, false
  for _, n in ipairs(numbers) do
    if n == number then
      held = true
    else
      out[#out + 1] = n
    end
  end
  return out, held
end

--- A: mark or unmark the PR under the cursor (pr://list) or the loaded one
--- (pr://files). One key both ways - there is no separate unmark, exactly as
--- D is both directions of draft.
function M.toggle()
  local root, p = require("pr").target()
  if not (root and p) then return warn "no PR here" end
  local numbers, held = without(M.numbers(root), p.number)
  if not held then numbers[#numbers + 1] = p.number end
  set(root, numbers)
end

--- Review the PR behind a mark. The row comes from pr.list.order when the
--- list is loaded, and otherwise from one forge call - a number alone cannot
--- name its base branch, and pr.load needs one.
---@param root string
---@param number integer
local function open(root, number)
  local list = require "pr.list"
  for _, p in ipairs(list.order) do
    if p.number == number then return require("pr").load(root, p) end
  end
  data.prs(root, function(prs, err)
    if not prs then return warn(err or "could not list PRs") end
    for _, p in ipairs(prs) do
      if p.number == number then return require("pr").load(root, p) end
    end
    -- Marked and no longer open: merged, or closed from somewhere else.
    -- There is nothing left to review, so offer to forget it rather than
    -- leaving a slot that fails the same way on every jump.
    local msg = ("#%d is not open any more. drop the mark?"):format(number)
    if vim.fn.confirm(msg, "&yes\n&no", 1) == 1 then set(root, (without(M.numbers(root), number))) end
  end)
end

--- <leader>N: straight to slot N, from anywhere.
---@param n integer
function M.slot(n)
  local root = M.root()
  if not root then return warn "not in a git repository" end
  local number = M.numbers(root)[n]
  if not number then return warn("no PR in slot " .. n) end
  open(root, number)
end

--- ]m / [m: the next mark along, wrapping. With no PR loaded, ]m enters at
--- slot 1 and [m at the last slot - the entry rule ]p / [p already use.
---@param delta 1|-1
function M.step(delta)
  local root = M.root()
  if not root then return warn "not in a git repository" end
  local numbers = M.numbers(root)
  local n = #numbers
  if n == 0 then return warn "no marked PRs - A marks the one under the cursor" end
  local s = require("pr").state
  local cur = 0
  for i, number in ipairs(numbers) do
    if s.pr and s.pr.number == number then
      cur = i
      break
    end
  end
  local nxt = cur == 0 and (delta > 0 and 1 or n) or ((cur - 1 + delta) % n) + 1
  open(root, numbers[nxt])
end

-- ------------------------------------------------------------------ peek ---

local ns = vim.api.nvim_create_namespace "pr_marks_peek"

--- <leader>0: the whole fast list at once, in a float over wherever you are.
--- The counterpart to <leader>1-9, which jump to a slot you already remember.
---
--- Titles come from pr.list.order when the list is loaded, and are simply
--- absent when it is not: the mark itself only ever knew the number, and a
--- float is not worth a forge call. The row still jumps - open() fetches what
--- pr.load needs on the way.
function M.peek()
  local root = M.root()
  if not root then return warn "not in a git repository" end
  local numbers = M.numbers(root)
  if #numbers == 0 then return warn "no marked PRs - A marks the one under the cursor" end

  local by_number = {}
  for _, p in ipairs(require("pr.list").order) do
    by_number[p.number] = p
  end
  local loaded = require("pr").state.pr

  local surface = require "pr.surface"
  local lines, marks, width = {}, {}, 0
  local seg = surface.segmenter(lines, marks)
  for slot, number in ipairs(numbers) do
    local p = by_number[number]
    local glyph, hl = surface.orb(p and p.ci)
    -- Same column order as a pr://list row, slot included, so the float reads
    -- as that list filtered rather than as a different thing.
    seg {
      { " " },
      { glyph, hl },
      { " " },
      { ("#%-5d"):format(number), p and p.isDraft and "Comment" or "DiagnosticOk" },
      { "  " },
      { tostring(slot), "Constant" },
      { " " },
      { p and p.title or "", loaded and loaded.number == number and "Underlined" or nil },
      { " " },
    }
    width = math.max(width, vim.fn.strdisplaywidth(lines[#lines]))
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  for _, m in ipairs(marks) do
    vim.api.nvim_buf_set_extmark(buf, ns, m[1], m[2], { end_col = m[3], hl_group = m[4] })
  end

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - #lines) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    width = math.min(width, vim.o.columns - 4),
    height = #lines,
    style = "minimal",
    border = "single",
    title = " fast list ",
    title_pos = "center",
  })
  vim.wo[win].cursorline = true
  -- Land on the PR being reviewed, so <CR> out of a peek is a no-op rather
  -- than a jump you did not ask for.
  for slot, number in ipairs(numbers) do
    if loaded and loaded.number == number then pcall(vim.api.nvim_win_set_cursor, win, { slot, 0 }) end
  end

  local o = { buffer = buf, silent = true, nowait = true }
  local function close()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end
  local function jump(slot)
    close()
    if numbers[slot] then open(root, numbers[slot]) end
  end
  vim.keymap.set("n", "<CR>", function() jump(vim.fn.line ".") end, o)
  for slot = 1, math.min(9, #numbers) do
    vim.keymap.set("n", tostring(slot), function() jump(slot) end, o)
  end
  -- dd, because the rows read as a list and that is what deleting a line in a
  -- list means. The float redraws so the slots renumber under the cursor.
  vim.keymap.set("n", "dd", function()
    local number = numbers[vim.fn.line "."]
    close()
    if number then
      set(root, (without(M.numbers(root), number)))
      M.peek()
    end
  end, o)
  for _, key in ipairs { "q", "<Esc>", "<leader>0" } do
    vim.keymap.set("n", key, close, o)
  end
  vim.api.nvim_create_autocmd("BufLeave", { buffer = buf, once = true, callback = close })
end

-- ------------------------------------------------------------------- maps ---

--- The mark keys, and the one source of what each one says it does.
M.KEYS = {
  { "A", M.toggle, "mark / unmark (fast list)" },
  { "]m", function() M.step(1) end, "next marked PR" },
  { "[m", function() M.step(-1) end, "prev marked PR" },
}

--- The mark keys, on every PR surface. `A` is a capital for the same reason
--- the verbs are: it is a no-op in a non-modifiable buffer, where a lowercase
--- `m` would shadow vim's own mark command, which still works there.
---@param buf integer
function M.attach(buf)
  for _, k in ipairs(M.KEYS) do
    vim.keymap.set("n", k[1], k[2], { buffer = buf, silent = true, desc = "pr: " .. k[3] })
  end
end

--- The mark rows for a g? help float. <leader>1-9 is global rather than a
--- buffer key, so it is named here rather than in M.KEYS.
---@return {[1]:string,[2]:string}[]
function M.help_entries()
  local out = {}
  for _, k in ipairs(M.KEYS) do
    out[#out + 1] = { k[1], k[3] }
  end
  out[#out + 1] = { "<leader>1-9", "jump to a marked slot" }
  out[#out + 1] = { "<leader>0", "the whole fast list, in a float" }
  return out
end

return M
