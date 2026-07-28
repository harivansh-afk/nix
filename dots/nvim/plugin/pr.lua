-- PR review flow. Lazy: nothing is required until a mapping fires.

local function pr(fn, ...)
  local args = { ... }
  return function() require("pr")[fn](unpack(args)) end
end

--- ]c / [c: commit navigation when a PR is loaded, vim's builtin diff-jump
--- in actual diff-mode windows. Buffer-local ]c maps (diffs.nvim hunk nav in
--- its own buffers) still win over this global one - deliberately.
local function step_or_builtin(delta, key)
  return function()
    if vim.wo.diff then return vim.cmd("normal! " .. key) end
    local mod = package.loaded["pr"]
    if mod and #mod.state.commits > 0 then return mod.step(delta) end
    pcall(vim.cmd, "normal! " .. key)
  end
end

--- ]p / [p: PR navigation when a pr://list is loaded, vim's builtin
--- paste-with-indent otherwise (same shape as ]c below).
local function step_pr_or_builtin(delta, key)
  return function()
    local list = package.loaded["pr.list"]
    if list and #list.order > 0 then return require("pr").step_pr(delta) end
    pcall(vim.cmd, "normal! " .. key)
  end
end

map("n", "<c-p>", pr "list", { desc = "pr: PR list" })
map("n", "]p", step_pr_or_builtin(1, "]p"), { desc = "pr: next PR / paste-indent" })
map("n", "[p", step_pr_or_builtin(-1, "[p"), { desc = "pr: prev PR / paste-indent" })
map("n", "<leader>gf", pr "files", { desc = "pr: files view" })
map("n", "<leader>gC", pr "pick_commit", { desc = "pr: pick commit in PR" })
map("n", "<leader>m", pr "toggle_mode", { desc = "pr: cumulative <-> incremental" })
map("n", "<leader>gA", pr "whole", { desc = "pr: whole PR view" })
map("n", "]c", step_or_builtin(1, "]c"), { desc = "pr: next commit / diff jump" })
map("n", "[c", step_or_builtin(-1, "[c"), { desc = "pr: prev commit / diff jump" })

vim.api.nvim_create_user_command("PR", function(opts)
  local sub = opts.args ~= "" and opts.args or "list"
  local actions = {
    list = "list",
    pick = "pick_pr",
    commit = "pick_commit",
    files = "files",
    mode = "toggle_mode",
    whole = "whole",
    refspec = "refspec",
  }
  local fn = actions[sub] or sub
  local mod = require "pr"
  if type(mod[fn]) ~= "function" then return vim.notify("pr: unknown subcommand " .. sub, vim.log.levels.ERROR) end
  mod[fn]()
end, {
  nargs = "?",
  complete = function() return { "list", "pick", "commit", "files", "mode", "whole", "refspec" } end,
  desc = "PR review flow",
})
