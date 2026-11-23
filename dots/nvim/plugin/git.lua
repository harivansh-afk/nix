map("n", "<C-g>", "<cmd>Git<cr><cmd>only<cr>")
map("n", "<leader>gc", "<cmd>Git commit<cr>")
map("n", "<leader>gp", "<cmd>Git push<cr>")
map("n", "<leader>gb", "<cmd>Git blame<cr>")
map("n", "<leader>gd", "<cmd>Gvdiffsplit<cr>")
map("n", "<leader>gr", "<cmd>Gread<cr>")
map("n", "<leader>gw", "<cmd>Gwrite<cr>")

map("n", "<C-p>", "<cmd>PR<cr>")
map("n", "<leader>gl", "<cmd>PR log<cr>")
map("n", "<leader>ci", "<cmd>PR checks<cr>")
map("n", "<leader>ct", "<cmd>PR threads<cr>")
map("n", "<C-e>", "<cmd>PR marks<cr>")
for slot = 1, 9 do
  map("n", "<leader>" .. slot, "<cmd>PR marks " .. slot .. "<cr>")
end
