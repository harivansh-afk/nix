-- PR review flow. Lazy: nothing is required until a mapping fires.

local function pr(fn, ...)
  local args = { ... }
  return function() require("pr")[fn](unpack(args)) end
end

--- A bracket pair that only means what pr means when the flow has something
--- to move through, and is vim's own key otherwise. Three of them now, so it
--- is written once: ]c is a diff jump outside a loaded PR (and always inside
--- a real diff-mode window - buffer-local ]c maps, diffs.nvim hunk nav in its
--- own buffers, still win over this global one), ]p is paste-with-indent
--- outside a PR list, ]m is a method motion with nothing on the fast list.
---
--- `ready` is asked on every press, so it must stay cheap and must never load
--- a pr module: `package.loaded` is what keeps the whole plugin lazy.
---@param key string
---@param ready fun(): boolean
---@param step fun()
local function nav(key, ready, step)
  return function()
    if ready() then return step() end
    pcall(vim.cmd, "normal! " .. key)
  end
end

local function in_pr()
  local mod = package.loaded["pr"]
  return not vim.wo.diff and mod ~= nil and #mod.state.commits > 0
end

local function in_list()
  local list = package.loaded["pr.list"]
  return list ~= nil and #list.order > 0
end

local function marked()
  local marks = package.loaded["pr.marks"]
  return marks ~= nil and marks.any()
end

map("n", "<c-p>", pr "list", { desc = "pr: PR list" })
map("n", "<leader>gl", pr "log", { desc = "pr: commit log" })
map("n", "]p", nav("]p", in_list, pr("step_pr", 1)), { desc = "pr: next PR / paste-indent" })
map("n", "[p", nav("[p", in_list, pr("step_pr", -1)), { desc = "pr: prev PR / paste-indent" })
map("n", "]m", nav("]m", marked, function() require("pr.marks").step(1) end), { desc = "pr: next marked PR" })
map("n", "[m", nav("[m", marked, function() require("pr.marks").step(-1) end), { desc = "pr: prev marked PR" })

--- <leader>1-9: straight to a slot on the fast list, from any buffer. Nine
--- because that is how many single keystrokes there are, and a fast list
--- longer than that is a PR list with extra steps.
for slot = 1, 9 do
  map("n", "<leader>" .. slot, function() require("pr.marks").slot(slot) end, { desc = "pr: fast list slot " .. slot })
end

--- <c-e>: the fast list itself, for when you want to look rather than
--- remember which slot. Harpoon's own quick-menu key, and it sits next to
--- <c-p> the way the fast list sits next to the PR list. It shadows
--- scroll-one-line-down, which <c-d> and <c-y> cover between them.
map("n", "<c-e>", function() require("pr.marks").peek() end, { desc = "pr: the fast list" })
map("n", "<leader>gf", pr "files", { desc = "pr: files view" })
map("n", "<leader>ci", pr "checks", { desc = "pr: CI checks pane" })
map("n", "<leader>ct", pr "threads", { desc = "pr: conversation pane" })
map("n", "<leader>gC", pr "pick_commit", { desc = "pr: pick commit in PR" })
map("n", "<leader>m", pr "toggle_mode", { desc = "pr: cumulative <-> incremental" })
map("n", "<leader>gA", pr "whole", { desc = "pr: whole PR view" })
map("n", "]c", nav("]c", in_pr, pr("step", 1)), { desc = "pr: next commit / diff jump" })
map("n", "[c", nav("[c", in_pr, pr("step", -1)), { desc = "pr: prev commit / diff jump" })

--- `:e` on a pr:// buffer. Without a BufReadCmd nvim treats the name as a
--- file path, finds nothing, and leaves the buffer wiped - so the handler
--- IS the load: pr://list re-fetches the PR list, pr://files re-reads the
--- loaded PR from origin. Both adopt the current buffer (see ensure_buf),
--- which is what makes `:e pr://list` work from a cold session too.
vim.api.nvim_create_autocmd("BufReadCmd", {
  pattern = "pr://list",
  callback = function() require("pr.list").open(true) end,
})
vim.api.nvim_create_autocmd("BufReadCmd", {
  pattern = "pr://log",
  callback = function() require("pr.log").open(nil, true) end,
})
vim.api.nvim_create_autocmd("BufReadCmd", {
  pattern = "pr://files",
  callback = function()
    local mod = require "pr"
    if #mod.state.commits == 0 then return mod.list() end -- nothing loaded: the list is the entry point
    require("pr.view").open()
    mod.reload()
  end,
})
--- `:e` on the CI pane asks the forge again, which is exactly what R does.
vim.api.nvim_create_autocmd("BufReadCmd", {
  pattern = "pr://checks",
  callback = function()
    local pane = require "pr.ci.pane"
    if pane.is_open() then return pane.refresh() end
    pane.open()
  end,
})
--- Same contract for the conversation pane.
vim.api.nvim_create_autocmd("BufReadCmd", {
  pattern = "pr://threads",
  callback = function()
    local pane = require "pr.threads.pane"
    if pane.is_open() then return pane.refresh() end
    pane.open()
  end,
})

local SUBS = {
  list = "list",
  log = "log",
  clean = "clean",
  pick = "pick_pr",
  commit = "pick_commit",
  files = "files",
  checks = "checks",
  threads = "threads",
  mode = "toggle_mode",
  whole = "whole",
  reload = "reload",
  refspec = "refspec",
}

--- Every verb is a subcommand too (:PR merge, :PR draft, ...), resolved out
--- of pr.verbs so the table can never fall behind the keymaps.
local function resolve(sub)
  if SUBS[sub] then return require("pr")[SUBS[sub]] end
  local verbs = require "pr.verbs"
  for _, k in ipairs(verbs.KEYS) do
    if k[2] == sub then return verbs[k[2]] end
  end
end

vim.api.nvim_create_user_command("PR", function(opts)
  local sub = opts.args ~= "" and opts.args or "list"
  local fn = resolve(sub)
  if not fn then return vim.notify("pr: unknown subcommand " .. sub, vim.log.levels.ERROR) end
  fn()
end, {
  nargs = "?",
  complete = function()
    local subs = vim.tbl_keys(SUBS)
    for _, k in ipairs(require("pr.verbs").KEYS) do
      subs[#subs + 1] = k[2]
    end
    table.sort(subs)
    return subs
  end,
  desc = "PR review flow",
})
