return {
  settings = {
    ["rust-analyzer"] = {
      checkOnSave = true,
      check = { command = "clippy" },
      cargo = { allFeatures = true },
      procMacro = { enable = true },
      completion = { autoimport = { enable = false } },
    },
  },
}
