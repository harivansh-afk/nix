vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("user_treesitter", { clear = true }),
  callback = function(ev)
    local lang = vim.treesitter.language.get_lang(vim.bo[ev.buf].filetype)
    if not (lang and vim.treesitter.language.add(lang)) then return end
    if pcall(vim.treesitter.start, ev.buf, lang) then
      vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
    end
  end,
})

local select_maps = {
  af = "@function.outer",
  ["if"] = "@function.inner",
  ac = "@class.outer",
  ic = "@class.inner",
  aa = "@parameter.outer",
  ia = "@parameter.inner",
}

return {
  {
    "nvim-treesitter-textobjects",
    after = function()
      require("nvim-treesitter-textobjects").setup {
        select = { lookahead = true },
      }

      for lhs, obj in pairs(select_maps) do
        map(
          { "x", "o" },
          lhs,
          function() require("nvim-treesitter-textobjects.select").select_textobject(obj, "textobjects") end
        )
      end
    end,
  },
}
