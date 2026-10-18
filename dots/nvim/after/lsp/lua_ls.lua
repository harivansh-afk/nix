return {
  settings = {
    Lua = {
      completion = { autoRequire = false },
      diagnostics = { globals = { "vim" } },
      runtime = { version = "LuaJIT" },
      workspace = {
        checkThirdParty = false,
        library = { vim.env.VIMRUNTIME },
      },
    },
  },
}
