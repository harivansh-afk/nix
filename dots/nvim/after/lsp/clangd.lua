return {
  filetypes = { "c", "cpp", "objc", "objcpp", "cuda" },
  cmd = {
    "clangd",
    "--clang-tidy",
    "-j=4",
    "--background-index",
    "--completion-style=bundled",
    "--header-insertion=iwyu",
    "--header-insertion-decorators=false",
  },
  capabilities = {
    textDocument = {
      completion = {
        editsNearCursor = true,
      },
    },
  },
}
