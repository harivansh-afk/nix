return {
    {
        'barrettruth/canola.nvim',
        branch = 'canola',
        dependencies = { 'nvim-tree/nvim-web-devicons' },
        init = function()
            vim.g.canola = {
                columns = { 'icon', 'git_status' },
                hidden = { enabled = false },
                keymaps = {
                    ['g?'] = { callback = 'actions.show_help', mode = 'n' },
                    ['<CR>'] = 'actions.select',
                    ['<C-v>'] = { callback = 'actions.select', opts = { vertical = true } },
                    ['<C-x>'] = { callback = 'actions.select', opts = { horizontal = true } },
                    ['<C-p>'] = 'actions.preview',
                    ['<C-c>'] = { callback = 'actions.close', mode = 'n' },
                    ['-'] = { callback = 'actions.parent', mode = 'n' },
                    ['g.'] = { callback = 'actions.toggle_hidden', mode = 'n' },
                },
            }
            map('n', '-', '<cmd>Canola<cr>')
            map('n', '<leader>e', '<cmd>Canola<cr>')
        end,
    },
    {
        'barrettruth/canola-collection',
        dependencies = { 'barrettruth/canola.nvim' },
    },
}
