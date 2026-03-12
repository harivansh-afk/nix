return {
    {
        'nvim-treesitter/nvim-treesitter',
        build = ':TSUpdate',
        dependencies = { 'nvim-treesitter/nvim-treesitter-textobjects' },
        config = function()
            require('nvim-treesitter.configs').setup({
                auto_install = true,
                highlight = { enable = true },
                indent = { enable = true },
                textobjects = {
                    select = {
                        enable = true,
                        lookahead = true,
                        keymaps = {
                            ['af'] = '@function.outer',
                            ['if'] = '@function.inner',
                            ['ac'] = '@class.outer',
                            ['ic'] = '@class.inner',
                            ['aa'] = '@parameter.outer',
                            ['ia'] = '@parameter.inner',
                            ['ai'] = '@conditional.outer',
                            ['ii'] = '@conditional.inner',
                            ['al'] = '@loop.outer',
                            ['il'] = '@loop.inner',
                            ['ab'] = '@block.outer',
                            ['ib'] = '@block.inner',
                        },
                    },
                    move = {
                        enable = true,
                        set_jumps = true,
                        goto_next_start = {
                            [']f'] = '@function.outer',
                            [']c'] = '@class.outer',
                            [']a'] = '@parameter.inner',
                        },
                        goto_next_end = {
                            [']F'] = '@function.outer',
                            [']C'] = '@class.outer',
                        },
                        goto_previous_start = {
                            ['[f'] = '@function.outer',
                            ['[c'] = '@class.outer',
                            ['[a'] = '@parameter.inner',
                        },
                        goto_previous_end = {
                            ['[F'] = '@function.outer',
                            ['[C'] = '@class.outer',
                        },
                    },
                    swap = {
                        enable = true,
                        swap_next = { ['<leader>sn'] = '@parameter.inner' },
                        swap_previous = { ['<leader>sp'] = '@parameter.inner' },
                    },
                },
            })
        end,
    },
}
