local function file_loc()
    local root = vim.trim(vim.fn.system('git rev-parse --show-toplevel'))
    if vim.v.shell_error ~= 0 or root == '' then
        return nil
    end
    local path = vim.api.nvim_buf_get_name(0)
    if path == '' or path:sub(1, #root + 1) ~= root .. '/' then
        return nil
    end
    return ('%s:%d'):format(path:sub(#root + 2), vim.fn.line('.'))
end

local function gh_browse()
    if vim.fn.executable('gh') ~= 1 then
        vim.notify('gh CLI not found', vim.log.levels.WARN)
        return
    end
    local loc = file_loc()
    if loc then
        vim.system({ 'gh', 'browse', loc })
    else
        vim.system({ 'gh', 'browse' })
    end
end

return {
    {
        'tpope/vim-fugitive',
        config = function()
            map('n', '<leader>gg', '<cmd>Git<cr><cmd>only<cr>')
            map('n', '<leader>gc', '<cmd>Git commit<cr>')
            map('n', '<leader>gp', '<cmd>Git push<cr>')
            map('n', '<leader>gl', '<cmd>Git pull<cr>')
            map('n', '<leader>gb', '<cmd>Git blame<cr>')
            map('n', '<leader>gd', '<cmd>Gvdiffsplit<cr>')
            map('n', '<leader>gr', '<cmd>Gread<cr>')
            map('n', '<leader>gw', '<cmd>Gwrite<cr>')
            map({ 'n', 'v' }, '<leader>go', gh_browse)
        end,
    },
    {
        'lewis6991/gitsigns.nvim',
        opts = {
            signs = {
                add          = { text = '██' },
                change       = { text = '██' },
                delete       = { text = '▄▄' },
                topdelete    = { text = '▀▀' },
                changedelete = { text = '██' },
            },
            signs_staged = {
                add          = { text = '▓▓' },
                change       = { text = '▓▓' },
                delete       = { text = '▄▄' },
                topdelete    = { text = '▀▀' },
                changedelete = { text = '▓▓' },
            },
            signs_staged_enable = true,
        },
        config = function(_, opts)
            require('gitsigns').setup(opts)
            map('n', ']g', '<cmd>Gitsigns next_hunk<cr>')
            map('n', '[g', '<cmd>Gitsigns prev_hunk<cr>')
            map('n', '<leader>ghs', '<cmd>Gitsigns stage_hunk<cr>')
            map('n', '<leader>ghr', '<cmd>Gitsigns reset_hunk<cr>')
            map('n', '<leader>ghp', '<cmd>Gitsigns preview_hunk<cr>')
            map('n', '<leader>gB', '<cmd>Gitsigns toggle_current_line_blame<cr>')
        end,
    },
    {
        'barrettruth/diffs.nvim',
        enabled = true,
        init = function()
            vim.g.diffs = {
                integrations = {
                    fugitive = {
                        enabled = true,
                        horizontal = false,
                        vertical = false,
                    },
                },
                hide_prefix = true,
                highlights = {
                    gutter = true,
                    blend_alpha = 0.5,
                    intra = { enabled = true },
                },
            }
        end,
    },
}
