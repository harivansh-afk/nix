vim.g.mapleader = " "
vim.g.maplocalleader = ","

vim.filetype.add { extension = { baml = "baml" } }

do
  local orig_notify = vim.notify
  vim.notify = function(msg, level, opts)
    if type(msg) == "string" and msg:find("Did not detect DSR response", 1, true) then return end
    return orig_notify(msg, level, opts)
  end
end

function _G.map(mode, lhs, rhs, opts)
  vim.keymap.set(mode, lhs, rhs, vim.tbl_extend("keep", opts or {}, { silent = true }))
end

vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.g.loaded_nvim_dir_plugin = 1

vim.cmd.packadd "nvim-treesitter"
vim.cmd.packadd "vim-fugitive"
vim.cmd.packadd "lz.n"

require("lz.n").load "plugins"
