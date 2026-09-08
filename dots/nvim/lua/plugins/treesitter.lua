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
  ai = "@conditional.outer",
  ii = "@conditional.inner",
  al = "@loop.outer",
  il = "@loop.inner",
  ab = "@block.outer",
  ib = "@block.inner",
}

local move_maps = {
  goto_next_start = { ["]f"] = "@function.outer", ["]c"] = "@class.outer", ["]a"] = "@parameter.inner" },
  goto_next_end = { ["]F"] = "@function.outer", ["]C"] = "@class.outer" },
  goto_previous_start = { ["[f"] = "@function.outer", ["[c"] = "@class.outer", ["[a"] = "@parameter.inner" },
  goto_previous_end = { ["[F"] = "@function.outer", ["[C"] = "@class.outer" },
}

return {
  {
    "nvim-treesitter-textobjects",
    after = function()
      require("nvim-treesitter-textobjects").setup {
        select = { lookahead = true },
        move = { set_jumps = true },
      }

      for lhs, obj in pairs(select_maps) do
        map(
          { "x", "o" },
          lhs,
          function() require("nvim-treesitter-textobjects.select").select_textobject(obj, "textobjects") end
        )
      end

      for method, maps in pairs(move_maps) do
        for lhs, obj in pairs(maps) do
          map(
            { "n", "x", "o" },
            lhs,
            function() require("nvim-treesitter-textobjects.move")[method](obj, "textobjects") end
          )
        end
      end

      map("n", "<leader>sn", function() require("nvim-treesitter-textobjects.swap").swap_next "@parameter.inner" end)
      map(
        "n",
        "<leader>sp",
        function() require("nvim-treesitter-textobjects.swap").swap_previous "@parameter.inner" end
      )
    end,
  },
}
