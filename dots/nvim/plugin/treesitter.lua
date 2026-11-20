vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("user_treesitter", { clear = true }),
  callback = function(ev)
    local lang = vim.treesitter.language.get_lang(vim.bo[ev.buf].filetype)
    if not (lang and vim.treesitter.language.add(lang)) then return end
    pcall(vim.treesitter.start, ev.buf, lang)
  end,
})
