local M = {}

function M.on_attach(_, bufnr)
    local function buf(mode, lhs, rhs)
        bmap(mode, lhs, rhs, { buffer = bufnr })
    end

    buf('n', 'gd', vim.lsp.buf.definition)
    buf('n', 'gD', vim.lsp.buf.declaration)
    buf('n', '<C-]>', vim.lsp.buf.definition)
    buf('n', 'gi', vim.lsp.buf.implementation)
    buf('n', 'gr', vim.lsp.buf.references)
    buf('n', 'K', vim.lsp.buf.hover)
    buf('n', '<leader>rn', vim.lsp.buf.rename)
    buf({ 'n', 'v' }, '<leader>ca', vim.lsp.buf.code_action)
    buf('n', '<leader>f', function() vim.lsp.buf.format({ async = true }) end)
end

function M.capabilities()
    return vim.lsp.protocol.make_client_capabilities()
end

return M
