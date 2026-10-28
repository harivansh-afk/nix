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

local dir_icons = api.nvim_create_namespace "dir.icons"
api.nvim_create_autocmd("User", {
  group = augroup,
  pattern = "DirReadPost",
  callback = function(args)
    local nonicons = require "nonicons"
    api.nvim_buf_clear_namespace(args.buf, dir_icons, 0, -1)
    for row, line in ipairs(api.nvim_buf_get_lines(args.buf, 0, -1, true)) do
      if line == "" then goto continue end
      local icon, hl
      if line:sub(-1) == "/" then
        icon, hl = nonicons.get "file-directory-fill", "Directory"
      else
        icon, hl = nonicons.get_icon(line)
      end
      if not icon then
        icon, hl = nonicons.get "file"
      end
      api.nvim_buf_set_extmark(
        args.buf,
        dir_icons,
        row - 1,
        0,
        { virt_text = { { icon .. " ", hl } }, virt_text_pos = "inline" }
      )
      ::continue::
    end
  end,
})
