return {
  {
    "cozybox.nvim",
    after = function() require("theme").setup() end,
  },
  {
    "nvim-web-devicons",
  },
  {
    "nonicons.nvim",
    before = function() vim.cmd.packadd "nvim-web-devicons" end,
  },
}
