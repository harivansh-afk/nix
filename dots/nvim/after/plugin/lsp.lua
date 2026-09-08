vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("ALsp", { clear = true }),
  callback = function(args)
    local function buf(mode, lhs, rhs) bmap(mode, lhs, rhs, { buffer = args.buf }) end

    buf("n", "gd", vim.lsp.buf.definition)
    buf("n", "gD", vim.lsp.buf.declaration)
    buf("n", "<C-]>", vim.lsp.buf.definition)
    buf("n", "gi", vim.lsp.buf.implementation)
    buf("n", "gr", vim.lsp.buf.references)
    buf("n", "K", vim.lsp.buf.hover)
    buf("n", "<leader>rn", vim.lsp.buf.rename)
    buf({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action)
    buf("n", "<leader>f", function() vim.lsp.buf.format { async = true } end)
  end,
})

local servers = {
  "bashls",
  "clangd",
  "cssls",
  "elixirls",
  "gopls",
  "html",
  "jsonls",
  "lua_ls",
  "pyright",
  "rust_analyzer",
  "ts_ls",
}

local available_servers = vim
  .iter(servers)
  :filter(function(name)
    local cmd = vim.lsp.config[name].cmd
    if type(cmd) == "function" then return true end
    return type(cmd) == "table" and type(cmd[1]) == "string" and vim.fn.executable(cmd[1]) == 1
  end)
  :totable()

vim.lsp.enable(available_servers)
