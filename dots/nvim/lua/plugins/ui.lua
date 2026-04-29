vim.pack.add({
  "https://github.com/harivansh-afk/cozybox.nvim",
  "https://github.com/barrettruth/nonicons.nvim",
  "https://github.com/nvim-tree/nvim-web-devicons",
}, { load = function() end })

return {
  {
    "harivansh-afk/cozybox.nvim",
    after = function()
      require("theme").setup()
      require("statusline").setup()
    end,
  },
  {
    "nvim-tree/nvim-web-devicons",
  },
  {
    "barrettruth/nonicons.nvim",
    before = function() vim.cmd.packadd "nvim-web-devicons" end,
  },
}
