vim.pack.add({
    'https://github.com/tpope/vim-fugitive',
})

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

map('n', '<C-g>', '<cmd>Git<cr><cmd>only<cr>')
map('n', '<leader>gg', '<cmd>Git<cr><cmd>only<cr>')
map('n', '<leader>gc', '<cmd>Git commit<cr>')
map('n', '<leader>gp', '<cmd>Git push<cr>')
map('n', '<leader>gl', '<cmd>Git pull<cr>')
map('n', '<leader>gb', '<cmd>Git blame<cr>')
map('n', '<leader>gd', '<cmd>Gvdiffsplit<cr>')
map('n', '<leader>gr', '<cmd>Gread<cr>')
map('n', '<leader>gw', '<cmd>Gwrite<cr>')
map({ 'n', 'v' }, '<leader>go', gh_browse)
