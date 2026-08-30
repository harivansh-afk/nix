local lsp = require "config.lsp"

vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("ALsp", { clear = true }),
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if client then lsp.on_attach(client, args.buf) end
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
