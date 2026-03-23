return {
    {
        'barrettruth/canola.nvim',
        branch = 'canola',
        dependencies = { 'nvim-tree/nvim-web-devicons' },
        init = function()
            vim.g.canola = {
                columns = { 'icon' },
                delete = { wipe = false, recursive = true },
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

            local ns = vim.api.nvim_create_namespace('canola_git_trailing')
            local symbols = {
                M = { '~', 'DiagnosticWarn' },
                A = { '+', 'DiagnosticOk' },
                D = { '-', 'DiagnosticError' },
                R = { '→', 'DiagnosticWarn' },
                ['?'] = { '?', 'DiagnosticInfo' },
                ['!'] = { '!', 'Comment' },
            }

            local function apply_git_status(buf)
                if not vim.api.nvim_buf_is_valid(buf) then return end
                vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

                local ok, canola = pcall(require, 'canola')
                if not ok then return end

                local dir = canola.get_current_dir(buf)
                if not dir then return end

                local git_ok, git = pcall(require, 'canola-git')
                if not git_ok then return end

                local dir_cache = git._cache[dir]
                if not dir_cache or not dir_cache.status then return end

                local lines = vim.api.nvim_buf_line_count(buf)
                for lnum = 0, lines - 1 do
                    local entry = canola.get_entry_on_line(buf, lnum + 1)
                    if entry then
                        local status = dir_cache.status[entry.name]
                        if status then
                            local ch = status:sub(1, 1)
                            if ch == ' ' then ch = status:sub(2, 2) end
                            local sym = symbols[ch]
                            if sym then
                                vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, {
                                    virt_text = { { ' ' .. sym[1], sym[2] } },
                                    virt_text_pos = 'eol',
                                    invalidate = true,
                                })
                            end
                        end
                    end
                end
            end

            vim.api.nvim_create_autocmd('User', {
                pattern = 'CanolaReadPost',
                callback = function(args)
                    local buf = args.buf
                    apply_git_status(buf)
                    vim.defer_fn(function() apply_git_status(buf) end, 500)
                end,
            })
        end,
    },
    {
        'barrettruth/canola-collection',
        dependencies = { 'barrettruth/canola.nvim' },
    },
}
