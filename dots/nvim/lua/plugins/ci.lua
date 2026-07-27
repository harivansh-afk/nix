-- GitHub Actions CI in a normal buffer, from the canola/diffs.nvim author.
-- Zero config: no setup() exists, `:CI` is the whole surface, and the
-- buffer-local mappings are only installed if the matching <Plug> target is
-- unmapped. Requirements (`gh`, `git`) are already in lib/nvim-packages.nix.
--
-- Lazy-loads on the command. That also gates the `ci://*` BufReadCmd handler
-- the plugin registers, so a bare `:e ci://...` in a fresh session does
-- nothing until `:CI` has loaded it once - navigating from `:CI` is unaffected.
vim.pack.add({
  "https://forge.barrettruth.com/barrettruth/ci.nvim",
}, { load = function() end })

return {
  {
    "barrettruth/ci.nvim",
    cmd = "CI",
    keys = {
      { "<leader>ci", "<cmd>CI<cr>", desc = "ci: checks for this PR" },
    },
  },
}
