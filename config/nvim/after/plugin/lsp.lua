pcall(vim.cmd.packadd, "blink.cmp")

local lsp = require "config.lsp"

vim.lsp.config("*", {
  on_attach = lsp.on_attach,
  capabilities = lsp.capabilities(),
})

for _, server in ipairs {
  "lua_ls",
  "pyright",
  "ts_ls",
  "rust_analyzer",
  "gopls",
  "clangd",
  "bashls",
  "jsonls",
  "html",
  "cssls",
} do
  local ok, config = pcall(require, "lsp." .. server)
  if ok and config then vim.lsp.config(server, config) end
  vim.lsp.enable(server)
end
