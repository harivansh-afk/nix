vim.pack.add({
  "https://github.com/echasnovski/mini.pairs",
  "https://github.com/nvim-mini/mini.completion",
  "https://github.com/kylechui/nvim-surround",
  "https://github.com/kevinhwang91/nvim-ufo",
  "https://github.com/kevinhwang91/promise-async",
  "https://github.com/barrettruth/preview.nvim",
}, { load = function() end })

return {
  {
    "echasnovski/mini.pairs",
    event = "InsertEnter",
    after = function() require("mini.pairs").setup() end,
  },
  {
    "nvim-mini/mini.completion",
    event = "InsertEnter",
    after = function()
      local completion = require "mini.completion"
      completion.setup {
        delay = { completion = 10000000, info = 100, signature = 50 },
        lsp_completion = {
          source_func = "omnifunc",
          auto_setup = false,
        },
        mappings = {
          force_twostep = "",
          force_fallback = "",
          scroll_down = "<c-f>",
          scroll_up = "<c-b>",
        },
      }

      local function set_omnifunc(bufnr)
        if not vim.api.nvim_buf_is_valid(bufnr) then return end
        for _, client in ipairs(vim.lsp.get_clients { bufnr = bufnr }) do
          if client:supports_method "textDocument/completion" then
            vim.bo[bufnr].omnifunc = "v:lua.MiniCompletion.completefunc_lsp"
            return
          end
        end
      end

      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("AMiniCompletionLsp", { clear = true }),
        callback = function(ev) set_omnifunc(ev.buf) end,
      })

      for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) then set_omnifunc(bufnr) end
      end

      local function pumvisible() return vim.fn.pumvisible() == 1 end

      vim.keymap.set("i", "<c-n>", function()
        if pumvisible() then return "<c-n>" end
        completion.complete_twostage()
        return ""
      end, { expr = true, desc = "complete next" })
      vim.keymap.set("i", "<c-p>", function() return pumvisible() and "<c-p>" or "" end, {
        expr = true,
        desc = "complete previous",
      })
      vim.keymap.set("i", "<c-t>", "<c-x><c-f>", { desc = "file completion" })
      vim.keymap.set("i", "<c-;>", "<c-x><c-v>", { desc = "vim command completion" })
      vim.keymap.set("i", "<c-r>", "<c-x><c-r>", { desc = "register completion" })
      vim.keymap.set("i", "<cr>", function()
        local cancel = pumvisible() and vim.keycode "<c-e>" or ""
        return cancel .. MiniPairs.cr()
      end, { expr = true, replace_keycodes = false, desc = "newline without accepting completion" })
    end,
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
