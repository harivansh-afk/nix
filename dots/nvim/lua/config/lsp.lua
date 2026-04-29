local M = {}

function M.on_attach(_, bufnr)
  local function buf(mode, lhs, rhs) bmap(mode, lhs, rhs, { buffer = bufnr }) end

  buf("n", "gd", vim.lsp.buf.definition)
  buf("n", "gD", vim.lsp.buf.declaration)
  buf("n", "<C-]>", vim.lsp.buf.definition)
  buf("n", "gi", vim.lsp.buf.implementation)
  buf("n", "gr", vim.lsp.buf.references)
  buf("n", "K", vim.lsp.buf.hover)
  buf("n", "<leader>rn", vim.lsp.buf.rename)
  buf({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action)
  buf("n", "<leader>f", function() vim.lsp.buf.format { async = true } end)
end

function M.capabilities()
  local capabilities = vim.lsp.protocol.make_client_capabilities()

  local ok_lz, lz = pcall(require, "lz.n")
  if ok_lz then
    pcall(lz.trigger_load, "saghen/blink.cmp")
  else
    pcall(vim.cmd.packadd, "blink.lib")
    pcall(vim.cmd.packadd, "blink.cmp")
  end

  local ok, blink = pcall(require, "blink.cmp")
  if ok and blink.get_lsp_capabilities then
    capabilities = vim.tbl_deep_extend("force", capabilities, blink.get_lsp_capabilities({}, false))
  end

  return capabilities
end

return M
