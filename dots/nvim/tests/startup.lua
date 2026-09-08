local function check()
  local errors = {}
  local notify = vim.notify
  vim.notify = function(msg, level, opts)
    if level == vim.log.levels.ERROR then errors[#errors + 1] = msg end
    return notify(msg, level, opts)
  end
  assert(not package.loaded["vim.pack"], "startup used the runtime installer")
  assert(vim.g.colors_name == "cozybox" or vim.g.colors_name == "cozybox-light", "theme missing")
  assert(vim.v.errmsg == "", vim.v.errmsg)
  local before_path = vim.env.NVIM_KEYMAP_BASELINE
  if before_path then
    local before = vim.json.decode(table.concat(vim.fn.readfile(before_path), "\n"))
    for mode, mappings in pairs(before) do
      local current = {}
      for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
        current[m.lhs] = m
      end
      for lhs, expected in pairs(mappings) do
        local actual = assert(current[lhs], "missing keymap: " .. mode .. " " .. lhs)
        for _, key in ipairs { "rhs", "expr", "noremap", "silent", "desc" } do
          assert(actual[key] == expected[key], "changed keymap: " .. mode .. " " .. lhs .. " " .. key)
        end
      end
    end
  end
  for _, name in ipairs {
    "canola.nvim",
    "fzf-lua",
    "forge.nvim",
    "gitsigns.nvim",
    "mini.pairs",
    "mini.completion",
    "nvim-surround",
    "nvim-ufo",
    "preview.nvim",
    "render-markdown.nvim",
  } do
    require("lz.n").trigger_load(name)
  end
  for _, command in ipairs { "Git", "Canola", "FzfLua", "Forge", "Preview", "RenderMarkdown", "ThemeSync" } do
    assert(vim.fn.exists(":" .. command) == 2, command .. " missing")
  end
  for _, lang in ipairs {
    "bash",
    "c",
    "lua",
    "nix",
    "python",
    "javascript",
    "typescript",
    "tsx",
    "json",
    "markdown",
    "markdown_inline",
  } do
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "value = 1" })
    assert(vim.treesitter.language.add(lang), lang .. " parser missing")
    assert(vim.treesitter.query.get(lang, "highlights"), lang .. " highlights missing")
    vim.treesitter.start(buf, lang)
    assert(vim.treesitter.highlighter.active[buf], lang .. " did not highlight")
    vim.api.nvim_buf_delete(buf, { force = true })
  end
  assert(require("nvim-treesitter").indentexpr, "Treesitter indentation missing")
  assert(MiniCompletion and MiniPairs, "completion or pairs missing")
  assert(#vim.fn.getcompletion("fzf-lua", "help") > 0, "plugin help tags missing")
  assert(#errors == 0, table.concat(errors, "\n"))
  print "Neovim smoke passed: keymaps, lazy loading, commands, completion, indentation, 11 parser/query pairs"
end
vim.defer_fn(function()
  local ok, err = xpcall(check, debug.traceback)
  if not ok then
    print(err)
    vim.cmd.cquit()
  else
    vim.cmd.qa()
  end
end, 100)
