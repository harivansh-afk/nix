---@param kind 'issue'|'pr'
---@param state 'all'|'open'|'closed'
local function gh_picker(kind, state)
    if vim.fn.executable('gh') ~= 1 then
        vim.notify('gh CLI not found', vim.log.levels.WARN)
        return
    end
    local next_state = ({ all = 'open', open = 'closed', closed = 'all' })[state]
    local label = kind == 'pr' and 'PRs' or 'Issues'
    require('fzf-lua').fzf_exec(('gh %s list --limit 100 --state %s'):format(kind, state), {
        prompt = ('%s (%s)> '):format(label, state),
        header = ':: <c-o> to toggle all/open/closed',
        actions = {
            ['default'] = function(selected)
                local num = selected[1]:match('^#?(%d+)')
                if num then
                    vim.system({ 'gh', kind, 'view', num, '--web' })
                end
            end,
            ['ctrl-o'] = function()
                gh_picker(kind, next_state)
            end,
        },
    })
end

return {
    'ibhagwan/fzf-lua',
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    config = function(_, opts)
        require('fzf-lua').setup(opts)

        map('n', '<C-f>', function()
            local fzf = require('fzf-lua')
            local git_dir = vim.fn.system('git rev-parse --git-dir 2>/dev/null'):gsub('\n', '')
            if vim.v.shell_error == 0 and git_dir ~= '' then
                fzf.git_files()
            else
                fzf.files()
            end
        end)
        map('n', '<leader>ff', '<cmd>FzfLua files<cr>')
        map('n', '<leader>fg', '<cmd>FzfLua live_grep<cr>')
        map('n', '<leader>fb', '<cmd>FzfLua buffers<cr>')
        map('n', '<leader>fh', '<cmd>FzfLua help_tags<cr>')
        map('n', '<leader>fr', '<cmd>FzfLua resume<cr>')
        map('n', '<leader>fo', '<cmd>FzfLua oldfiles<cr>')
        map('n', '<leader>fc', '<cmd>FzfLua commands<cr>')
        map('n', '<leader>fk', '<cmd>FzfLua keymaps<cr>')
        map('n', '<leader>f/', '<cmd>FzfLua search_history<cr>')
        map('n', '<leader>f:', '<cmd>FzfLua command_history<cr>')
        map('n', '<leader>fe', '<cmd>FzfLua files cwd=~/.config<cr>')
        map('n', 'gq', '<cmd>FzfLua quickfix<cr>')
        map('n', 'gl', '<cmd>FzfLua loclist<cr>')
        map('n', '<leader>GB', '<cmd>FzfLua git_branches<cr>')
        map('n', '<leader>Gc', '<cmd>FzfLua git_commits<cr>')
        map('n', '<leader>Gs', '<cmd>FzfLua git_status<cr>')
        map('n', '<leader>Gp', function() gh_picker('pr', 'open') end)
        map('n', '<leader>Gi', function() gh_picker('issue', 'open') end)
    end,
    opts = {
        'default-title',
        winopts = {
            border = 'single',
            preview = {
                layout = 'vertical',
                vertical = 'down:50%',
            },
        },
        fzf_opts = {
            ['--layout'] = 'reverse',
        },
    },
}
