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

map("n", "<leader>gP", pr "pick_pr", { desc = "pr: pick PR" })
map("n", "<leader>gf", pr "files", { desc = "pr: files view" })
map("n", "<leader>gC", pr "pick_commit", { desc = "pr: pick commit in PR" })
map("n", "<leader>gm", pr "toggle_mode", { desc = "pr: cumulative <-> incremental" })
map("n", "<leader>gA", pr "whole", { desc = "pr: whole PR view" })
map("n", "]c", step_or_builtin(1, "]c"), { desc = "pr: next commit / diff jump" })
map("n", "[c", step_or_builtin(-1, "[c"), { desc = "pr: prev commit / diff jump" })

vim.api.nvim_create_user_command("PR", function(opts)
  local sub = opts.args ~= "" and opts.args or "pick_pr"
  local actions = {
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
  complete = function() return { "pick", "commit", "files", "mode", "whole", "refspec" } end,
  desc = "PR review flow",
})
