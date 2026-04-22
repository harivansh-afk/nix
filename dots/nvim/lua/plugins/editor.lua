vim.pack.add({
  "https://github.com/windwp/nvim-autopairs",
  "https://github.com/folke/flash.nvim",
  "https://github.com/kylechui/nvim-surround",
  "https://github.com/kevinhwang91/nvim-ufo",
  "https://github.com/kevinhwang91/promise-async",
  "https://github.com/barrettruth/preview.nvim",
}, { load = function() end })

return {
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    after = function() require("nvim-autopairs").setup() end,
  },
  {
    "folke/flash.nvim",
    after = function()
      require("flash").setup {
        modes = { search = { enabled = true } },
      }
    end,
    keys = {
      {
        "s",
        function() require("flash").jump() end,
        mode = { "n", "x", "o" },
      },
      {
        "S",
        function() require("flash").treesitter() end,
        mode = { "n", "x", "o" },
      },
      {
        "r",
        function() require("flash").remote() end,
        mode = "o",
      },
      {
        "R",
        function() require("flash").treesitter_search() end,
        mode = { "o", "x" },
      },
      {
        "<c-s>",
        function() require("flash").toggle() end,
        mode = "c",
      },
    },
  },
  {
    "kylechui/nvim-surround",
    after = function() require("nvim-surround").setup() end,
    keys = {
      { "cs", mode = "n" },
      { "ds", mode = "n" },
      { "ys", mode = "n" },
      { "yS", mode = "n" },
      { "yss", mode = "n" },
      { "ySs", mode = "n" },
    },
  },
  {
    "kevinhwang91/nvim-ufo",
    event = "BufReadPost",
    before = function() vim.cmd.packadd "promise-async" end,
    after = function()
      require("ufo").setup {
        provider_selector = function() return { "treesitter", "indent" } end,
      }
    end,
    keys = {
      {
        "zR",
        function() require("ufo").openAllFolds() end,
        mode = "n",
      },
      {
        "zM",
        function() require("ufo").closeAllFolds() end,
        mode = "n",
      },
    },
  },
  {
    "barrettruth/preview.nvim",
    cmd = "Preview",
    ft = { "markdown", "tex", "typst" },
    before = function()
      vim.g.preview = {
        typst = true,
        latex = true,
        github = {
          output = function(ctx) return "/tmp/" .. vim.fn.fnamemodify(ctx.file, ":t:r") .. ".html" end,
        },
        mermaid = true,
      }
    end,
  },
}
