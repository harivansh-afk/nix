map("n", "<C-g>", "<cmd>Git<cr><cmd>only<cr>")
map("n", "<leader>gc", "<cmd>Git commit<cr>")
map("n", "<leader>gp", "<cmd>Git push<cr>")
map("n", "<leader>gb", "<cmd>Git blame<cr>")
map("n", "<leader>gd", "<cmd>Gvdiffsplit<cr>")
map("n", "<leader>gr", "<cmd>Gread<cr>")
map("n", "<leader>gw", "<cmd>Gwrite<cr>")

vim.api.nvim_create_autocmd("User", {
  pattern = "FugitiveIndex",
  group = vim.api.nvim_create_augroup("gitstats_fugitive", { clear = true }),
  callback = function(ev) require("pr.gitstats").fugitive(ev.buf) end,
})
