return {
    'saghen/blink.cmp',
    version = '*',
    event = { 'InsertEnter', 'LspAttach' },
    opts = {
        keymap = {
            ['<Tab>'] = { 'select_and_accept', 'snippet_forward', 'fallback' },
            ['<S-Tab>'] = { 'snippet_backward', 'fallback' },
            ['<c-p>'] = { 'select_prev', 'fallback' },
            ['<c-n>'] = { 'show', 'select_next', 'fallback' },
            ['<c-y>'] = { 'select_and_accept', 'fallback' },
            ['<c-e>'] = { 'cancel', 'fallback' },
            ['<c-u>'] = { 'scroll_documentation_up', 'fallback' },
            ['<c-d>'] = { 'scroll_documentation_down', 'fallback' },
        },
        cmdline = { enabled = false },
        completion = {
            accept = {
                auto_brackets = { enabled = true },
            },
            documentation = {
                auto_show = true,
                window = {
                    border = 'single',
                    scrollbar = false,
                },
            },
            menu = {
                auto_show = true,
                border = 'single',
                scrollbar = false,
                draw = {
                    treesitter = { 'lsp' },
                    columns = {
                        { 'label', 'label_description', gap = 1 },
                        { 'kind' },
                    },
                },
            },
            ghost_text = { enabled = true },
        },
        sources = {
            default = { 'lsp', 'path', 'buffer', 'snippets' },
        },
    },
}
