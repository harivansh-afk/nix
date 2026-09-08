return {
  {
    "render-markdown.nvim",
    ft = "markdown",
    after = function()
      require("render-markdown").setup {
        completions = { lsp = { enabled = true } },
      }
    end,
    keys = {
      { "<leader>tm", "<cmd>RenderMarkdown toggle<cr>", mode = "n", desc = "Toggle render-markdown" },
    },
  },
}
