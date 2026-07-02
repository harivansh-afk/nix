-- agentdiff wiring: fzf worktree picker + auto-open the live agent's diff on
-- startup. See lua/agentdiff.lua. Disable auto with:
--   vim.g.agentdiff = { auto = false }

map("n", "<leader>aw", function() require("agentdiff").pick() end)

vim.api.nvim_create_autocmd("VimEnter", {
  group = vim.api.nvim_create_augroup("agentdiff_auto", { clear = true }),
  nested = true,
  callback = function() require("agentdiff").auto() end,
})
