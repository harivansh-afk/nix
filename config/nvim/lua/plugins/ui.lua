return {
  {
    "harivansh-afk/cozybox.nvim",
    lazy = false,
    priority = 1000,
    config = function() require("theme").setup() end,
  },
  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      local theme_status = function() return require("theme").statusline_label() end
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
  {
    "barrettruth/nonicons.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
  },
}
