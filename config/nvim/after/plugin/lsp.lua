local lsp = require('config.lsp')

vim.lsp.config('*', {
    capabilities = lsp.capabilities(),
})

vim.api.nvim_create_autocmd('LspAttach', {
    group = vim.api.nvim_create_augroup('UserLspConfig', {}),
    callback = function(ev)
        local client = vim.lsp.get_client_by_id(ev.data.client_id)
        if client then
            lsp.on_attach(client, ev.buf)
        end
    end,
})

for _, server in ipairs({
    'lua_ls',
    'pyright',
    'ts_ls',
    'rust_analyzer',
    'gopls',
    'clangd',
    'bashls',
    'jsonls',
    'html',
    'cssls',
}) do
    local ok, config = pcall(require, 'lsp.' .. server)
    if ok then
        vim.lsp.config(server, config)
    end
    vim.lsp.enable(server)
end
