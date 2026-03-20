return {
    {
        'ellisonleao/gruvbox.nvim',
        lazy = false,
        priority = 1000,
        config = function()
            require('gruvbox').setup({
                contrast = 'hard',
                transparent_mode = false,
                italic = { comments = true },
                overrides = {
                    MatchParen = { bold = true, underline = true, fg = '#d8a657', bg = '#3c3836' },
                    Normal = { bg = '#181818' },
                    NormalFloat = { bg = '#181818' },
                    SignColumn = { bg = '#181818' },
                    StatusLine = { bg = '#181818' },
                    StatusLineNC = { bg = '#181818' },
                    GruvboxOrange = { fg = '#bdae93' },
                    GruvboxOrangeBold = { fg = '#bdae93', bold = true },
                    ['@operator'] = { fg = '#bdae93' },
                    Delimiter = { fg = '#bdae93' },
                    ['@punctuation.bracket'] = { fg = '#bdae93' },
                    ['@punctuation.delimiter'] = { fg = '#bdae93' },
                    GitSignsAdd = { fg = '#a9b665', bg = '#181818' },
                    GitSignsChange = { fg = '#d8a657', bg = '#181818' },
                    GitSignsDelete = { fg = '#ea6962', bg = '#181818' },
                    GitSignsTopdelete = { fg = '#ea6962', bg = '#181818' },
                    GitSignsChangedelete = { fg = '#d8a657', bg = '#181818' },
                    GitSignsUntracked = { fg = '#7daea3', bg = '#181818' },
                    GitSignsStagedAdd = { fg = '#6c7842', bg = '#181818' },
                    GitSignsStagedChange = { fg = '#8a6d39', bg = '#181818' },
                    GitSignsStagedDelete = { fg = '#94433f', bg = '#181818' },
                    GitSignsStagedTopdelete = { fg = '#94433f', bg = '#181818' },
                    GitSignsStagedChangedelete = { fg = '#8a6d39', bg = '#181818' },
                    LineNr = { bg = '#181818' },
                    CursorLineNr = { bg = '#181818' },
                    CursorLine = { bg = '#1e1e1e' },
                    FoldColumn = { bg = '#181818' },
                    DiffAdd = { bg = '#1e2718' },
                    DiffChange = { bg = '#1e1e18' },
                    DiffDelete = { bg = '#2a1818' },
                },
            })
            vim.cmd.colorscheme('gruvbox')
        end,
    },
    {
        'nvim-lualine/lualine.nvim',
        dependencies = { 'nvim-tree/nvim-web-devicons' },
        config = function()
            local bg = '#181818'
            local fg = '#d4be98'
            local gray = '#7c6f64'
            local theme = {
                normal = {
                    a = { bg = bg, fg = fg, gui = 'bold' },
                    b = { bg = bg, fg = fg },
                    c = { bg = bg, fg = gray },
                },
                insert = {
                    a = { bg = bg, fg = '#a9b665', gui = 'bold' },
                },
                visual = {
                    a = { bg = bg, fg = '#d3869b', gui = 'bold' },
                },
                replace = {
                    a = { bg = bg, fg = '#ea6962', gui = 'bold' },
                },
                command = {
                    a = { bg = bg, fg = '#d8a657', gui = 'bold' },
                },
                inactive = {
                    a = { bg = bg, fg = gray },
                    b = { bg = bg, fg = gray },
                    c = { bg = bg, fg = gray },
                },
            }
            require('lualine').setup({
                options = {
                    theme = theme,
                    icons_enabled = false,
                    component_separators = '',
                    section_separators = { left = '', right = '' },
                },
                sections = {
                    lualine_a = { 'mode' },
                    lualine_b = { 'FugitiveHead', 'diff' },
                    lualine_c = { { 'filename', path = 0 } },
                    lualine_x = { 'diagnostics' },
                    lualine_y = { 'filetype' },
                    lualine_z = { 'progress' },
                },
            })
        end,
    },
    {
        'barrettruth/nonicons.nvim',
        dependencies = { 'nvim-tree/nvim-web-devicons' },
    },
}
