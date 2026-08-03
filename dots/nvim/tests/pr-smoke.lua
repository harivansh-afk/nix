-- Assertions for scripts/pr-smoke.sh, which is how CI runs this: headless,
-- with dots/nvim prepended to 'runtimepath' and nothing else loaded, so a
-- require here resolves to the checkout under test rather than the user's
-- live config.
--
-- Everything is offline: the forge and git are stubbed on pr.data, because
-- what is defended here is the plugin's own behaviour, not the forge's.

local failures = 0

local function check(name, ok, extra)
  if not ok then failures = failures + 1 end
  print(("%-52s %s%s"):format(name, ok and "ok" or "FAIL", extra and ("  " .. tostring(extra)) or ""))
end

-- Every module loads. A syntax error or a require that no longer resolves
-- fails here rather than the first time a key is pressed.
for _, mod in ipairs {
  "pr",
  "pr.run",
  "pr.data",
  "pr.fmt",
  "pr.surface",
  "pr.marks",
  "pr.verbs",
  "pr.list",
  "pr.log",
  "pr.view",
  "pr.pick",
  "pr.tree",
  "pr.ci",
  "pr.ci.api",
  "pr.ci.ansi",
  "pr.ci.pane",
  "pr.ci.log",
} do
  local ok, err = pcall(require, mod)
  check("require " .. mod, ok, not ok and err or nil)
end

vim.cmd "runtime! plugin/pr.lua"
local maps = {}
for _, m in ipairs(vim.api.nvim_get_keymap "n") do
  maps[m.lhs] = true
end
-- mapleader is a space above, and nvim reports the lhs with it resolved.
for _, lhs in ipairs { "]p", "[p", "]c", "[c", "]m", "[m", " 1", " 9", "<C-E>" } do
  check("global map " .. lhs, maps[lhs] == true)
end

-- ------------------------------------------------------------------ marks ---

local data = require "pr.data"
local marks = require "pr.marks"
local list = require "pr.list"

local ROOT = "/pr-smoke-repo"
local FIXTURE = {
  { number = 385, title = "a title", author = { login = "hari" }, baseRefName = "main", headRefName = "one" },
  { number = 366, title = "another title", author = { login = "hari" }, baseRefName = "main", headRefName = "two" },
}

data.root = function() return ROOT end
data.has_refspec = function() return true end
data.prs = function(_, cb) cb(vim.deepcopy(FIXTURE)) end
data.pr_heads = function() return {} end
require("pr.ci").prime = function() end

list.open()
check("the list rendered its rows", #list.order == 2, #list.order)

local buf = vim.fn.bufnr "pr://list"
local function row(n) return vim.api.nvim_buf_get_lines(buf, n - 1, n, false)[1] or "" end
local before = vim.fn.strdisplaywidth(row(2))

vim.api.nvim_win_set_cursor(0, { 2, 0 })
marks.toggle()

-- The slot column is the cell between the PR number and the title, found
-- from the number rather than a byte offset because the orb is multibyte:
-- "#%-5d" is six cells, then the two-space gap.
local function slot_cell(line, number)
  local at = line:find("#" .. number, 1, true)
  return at and line:sub(at + 8, at + 8)
end

check("toggle marked the row under the cursor", vim.deep_equal(marks.numbers(ROOT), { 366 }))
check("the mark renders as its slot digit", slot_cell(row(2), 366) == "1", row(2):sub(1, 26))
check("it sits immediately left of the title", row(2):find("1 another title", 1, true) ~= nil, row(2):sub(1, 30))
-- The column is charged to the title width and spent on every row, so no
-- column moves when a row is marked. That property is the whole placement.
check("marking re-flows nothing", vim.fn.strdisplaywidth(row(2)) == before, before)
check("an unmarked row keeps a blank slot", slot_cell(row(1), 385) == " ", row(1):sub(1, 26))

vim.api.nvim_win_set_cursor(0, { 1, 0 })
marks.toggle()
check("slots are insertion order", vim.deep_equal(marks.numbers(ROOT), { 366, 385 }))
check("the second slot renders 2", slot_cell(row(1), 385) == "2", row(1):sub(1, 26))

-- The store on disk is what the next session reads.
local file = vim.fs.joinpath(vim.fn.stdpath "state", "pr-marks.json")
local disk = vim.json.decode(table.concat(vim.fn.readfile(file), "\n"))
check("marks persist under their repo root", vim.deep_equal(disk[ROOT], { 366, 385 }), vim.inspect(disk))

-- --------------------------------------------------------------- the peek ---

-- <leader>0: the whole list in a float, one row per slot, with the titles the
-- loaded pr://list already knows.
local list_win = vim.api.nvim_get_current_win()
marks.peek()
local peek_win = vim.api.nvim_get_current_win()
check("peek opened a float", peek_win ~= list_win and vim.api.nvim_win_get_config(peek_win).relative ~= "")
local peek = vim.api.nvim_buf_get_lines(0, 0, -1, false)
check("peek has a row per mark", #peek == 2, vim.inspect(peek))
check(
  "peek matches the list's columns",
  slot_cell(peek[1], 366) == "1" and peek[1]:find("1 another title", 1, true) ~= nil,
  peek[1]
)

-- dd drops the row under the cursor and the float comes back renumbered.
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.cmd "normal dd"
check("dd drops that mark", vim.deep_equal(marks.numbers(ROOT), { 385 }), vim.inspect(marks.numbers(ROOT)))
peek = vim.api.nvim_buf_get_lines(0, 0, -1, false)
check("the peek renumbers", #peek == 1 and slot_cell(peek[1], 385) == "1", peek[1])
vim.cmd "normal q"
check("q closes the peek", vim.api.nvim_get_current_win() == list_win)

vim.api.nvim_win_set_cursor(0, { 1, 0 })
marks.toggle()
check("toggle is its own undo", #marks.numbers(ROOT) == 0)
disk = vim.json.decode(table.concat(vim.fn.readfile(file), "\n"))
check("an empty list drops its key", disk[ROOT] == nil, vim.inspect(disk))

-- ---------------------------------------------------------------- the keys ---

-- Every PR buffer answers to both refresh keys and to the shared verbs and
-- marks. A surface that grows its own local R is what this catches.
local bmaps = {}
for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
  bmaps[m.lhs] = true
end
for _, lhs in ipairs { "R", "<C-R>", "A", "]m", "[m", "D", "M", "C", "O", "X", "<CR>", "g?", "q" } do
  check("pr://list map " .. lhs, bmaps[lhs] == true)
end

local hits = 0
local scratch = vim.api.nvim_create_buf(false, true)
require("pr.surface").common_keys(scratch, function() hits = hits + 1 end)
vim.api.nvim_set_current_buf(scratch)
vim.cmd "normal R"
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<c-r>", true, false, true), "x", false)
check("R and <c-r> both refresh", hits == 2, hits)

local rows, seen = require("pr.surface").common_help(), {}
for _, r in ipairs(rows) do
  seen[r[1]] = (seen[r[1]] or 0) + 1
end
for _, key in ipairs { "A", "]m", "[m", "<leader>1-9", "<c-e>", "D", "M" } do
  check("g? documents " .. key, seen[key] == 1)
end

print(failures == 0 and "\npr smoke: ok" or ("\npr smoke: " .. failures .. " failures"))
vim.cmd(failures == 0 and "qall!" or "cquit")
