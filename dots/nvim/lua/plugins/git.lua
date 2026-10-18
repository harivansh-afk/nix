return {
  {
    "pr.nvim",
    priority = 0,
    after = function() require("pr").setup { keymaps = true } end,
  },
  {
    "gitsigns.nvim",
    event = "BufReadPre",
    after = function()
      require("gitsigns").setup {
        base = "HEAD",
        signs = {
          add = { text = "██" },
          change = { text = "██" },
          delete = { text = "▄▄" },
          topdelete = { text = "▀▀" },
          changedelete = { text = "██" },
        },
        signs_staged = {
          add = { text = "▓▓" },
          change = { text = "▓▓" },
          delete = { text = "▄▄" },
          topdelete = { text = "▀▀" },
          changedelete = { text = "▓▓" },
        },
        signs_staged_enable = true,
      }

      map("n", "]g", "<cmd>Gitsigns nav_hunk next<cr>")
      map("n", "[g", "<cmd>Gitsigns nav_hunk prev<cr>")
      map("n", "<leader>ghs", "<cmd>Gitsigns stage_hunk<cr>")
      map("n", "<leader>ghr", "<cmd>Gitsigns reset_hunk<cr>")
      map("n", "<leader>ghp", "<cmd>Gitsigns preview_hunk<cr>")
      map("n", "<leader>gB", "<cmd>Gitsigns toggle_current_line_blame<cr>")
    end,
  },
  {
    "diffs.nvim",
    before = function()
      vim.g.diffs = {
        integrations = {
          fugitive = true,
        },
        view = {
          prefix = false,
        },
        highlights = {
          warn_max_lines = false,
          blend_alpha = 0.5,
          intra = { enabled = true },
        },
      }
    end,
  },
}
