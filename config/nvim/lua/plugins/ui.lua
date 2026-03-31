vim.pack.add({
  "https://github.com/harivansh-afk/cozybox.nvim",
  "https://github.com/nvim-lualine/lualine.nvim",
  "https://github.com/barrettruth/nonicons.nvim",
  "https://github.com/nvim-tree/nvim-web-devicons",
}, { load = function() end })

return {
  {
    "harivansh-afk/cozybox.nvim",
    after = function() require("theme").setup() end,
  },
  {
    "nvim-tree/nvim-web-devicons",
  },
  {
    "barrettruth/nonicons.nvim",
    before = function() vim.cmd.packadd "nvim-web-devicons" end,
  },
  {
    "nvim-lualine/lualine.nvim",
    before = function()
      vim.cmd.packadd "nvim-web-devicons"
      pcall(vim.cmd.packadd, "nonicons.nvim")
    end,
    after = function()
      local theme = {
        normal = {
          a = { gui = "bold" },
        },
        visual = {
          a = { gui = "bold" },
        },
        replace = {
          a = { gui = "bold" },
        },
        command = {
          a = { gui = "bold" },
        },
      }

      require("lualine").setup {
        options = {
          icons_enabled = false,
          component_separators = "",
          section_separators = { left = "", right = "" },
          theme = theme,
        },
        sections = {
          lualine_a = { "mode" },
          lualine_b = { "FugitiveHead", "diff" },
          lualine_c = { { "filename", path = 0 } },
          lualine_x = {},
          lualine_y = {},
          lualine_z = { "progress" },
        },
      }
    end,
  },
}
