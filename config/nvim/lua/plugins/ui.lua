return {
    {
        'harivansh-afk/cozybox.nvim',
        lazy = false,
        priority = 1000,
        config = function()
            local function apply_cozybox_overrides()
                local links = {
                    { 'DiffsAdd', 'DiffAdd' },
                    { 'DiffsDelete', 'DiffDelete' },
                    { 'DiffsChange', 'DiffChange' },
                    { 'DiffsText', 'DiffText' },
                    { 'DiffsClear', 'Normal' },
                }
                for _, pair in ipairs(links) do
                    vim.api.nvim_set_hl(0, pair[1], { link = pair[2], default = false })
                end
            end

            vim.api.nvim_create_augroup('cozybox_fallback_highlights', { clear = true })
            vim.api.nvim_create_autocmd('ColorScheme', {
                group = 'cozybox_fallback_highlights',
                callback = function()
                    if vim.g.colors_name == 'cozybox' then
                        apply_cozybox_overrides()
                    end
                end,
            })

            vim.cmd.colorscheme('cozybox')
            apply_cozybox_overrides()
        end,
    },
    {
        'nvim-lualine/lualine.nvim',
        dependencies = { 'nvim-tree/nvim-web-devicons' },
        config = function()
            local theme = {
                normal = {
                    a = { gui = 'bold' },
                },
                visual = {
                    a = { gui = 'bold' },
                },
                replace = {
                    a = { gui = 'bold' },
                },
                command = {
                    a = { gui = 'bold' },
                },
            }
            require('lualine').setup({
                options = {
                    icons_enabled = false,
                    component_separators = '',
                    section_separators = { left = '', right = '' },
                    theme = theme,
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
