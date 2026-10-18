return {
  { "vim-eunuch" },
  {
    "mini.pairs",
    event = "InsertEnter",
    after = function()
      require("mini.pairs").setup()

      local function pumvisible() return vim.fn.pumvisible() == 1 end

      vim.keymap.set("i", "<c-n>", function()
        if pumvisible() then return "<c-n>" end
        return vim.bo.omnifunc ~= "" and "<c-x><c-o>" or "<c-n>"
      end, { expr = true, desc = "complete next" })
      vim.keymap.set("i", "<cr>", function()
        if pumvisible() then return vim.keycode(vim.fn.complete_info().selected == -1 and "<c-n><c-y>" or "<c-y>") end
        return MiniPairs.cr()
      end, { expr = true, replace_keycodes = false, desc = "accept completion or newline" })
    end,
  },
  {
    "nvim-surround",
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
    "mini.pick",
    cmd = "Pick",
    after = function() require("mini.pick").setup() end,
    keys = {
      { "<C-f>", "<cmd>Pick files<cr>" },
      { "<C-s>", "<cmd>Pick grep_live<cr>" },
      { "<leader>ff", "<cmd>Pick files<cr>" },
      { "<leader>fg", "<cmd>Pick grep_live<cr>" },
      { "<leader>fb", "<cmd>Pick buffers<cr>" },
      { "<leader>fh", "<cmd>Pick help<cr>" },
      { "<leader>fr", "<cmd>Pick resume<cr>" },
    },
  },
}
