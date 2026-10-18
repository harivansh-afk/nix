local api = vim.api
local augroup = api.nvim_create_augroup("UserAutocmds", { clear = true })

api.nvim_create_autocmd("BufReadPost", {
  group = augroup,
  callback = function()
    if ({ gitcommit = true, gitrebase = true })[vim.bo.filetype] then return end
    local mark = api.nvim_buf_get_mark(0, '"')
    if mark[1] > 0 and mark[1] <= api.nvim_buf_line_count(0) then pcall(api.nvim_win_set_cursor, 0, mark) end
  end,
})

api.nvim_create_autocmd("TermOpen", {
  group = augroup,
  callback = function() vim.cmd.startinsert() end,
})
