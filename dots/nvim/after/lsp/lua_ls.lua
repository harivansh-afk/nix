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
      telemetry = { enable = false },
      hint = { enable = true },
    },
  },
}
