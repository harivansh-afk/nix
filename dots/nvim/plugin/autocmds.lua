local api = vim.api
local augroup = api.nvim_create_augroup("UserAutocmds", { clear = true })

local function ensure_canola_loaded()
  local canola_config = require "config.canola"
  canola_config.setup_globals()

  local ok_lz, lz = pcall(require, "lz.n")
  if ok_lz then pcall(lz.trigger_load, "barrettruth/canola.nvim") end

  if vim.fn.exists ":Canola" ~= 2 then pcall(vim.cmd.packadd, "canola.nvim") end

  canola_config.setup_integrations()
end

local function maybe_load_canola(bufnr)
  local name = api.nvim_buf_get_name(bufnr)
  if name == "" or vim.bo[bufnr].filetype == "canola" or vim.fn.isdirectory(name) == 0 then return end

  ensure_canola_loaded()
  pcall(vim.cmd, "silent keepalt Canola " .. vim.fn.fnameescape(name))
end

api.nvim_create_autocmd("TextYankPost", {
  group = augroup,
  callback = function() vim.highlight.on_yank { higroup = "Visual", timeout = 200 } end,
})

api.nvim_create_autocmd("BufReadPost", {
  group = augroup,
  callback = function()
    if ({ gitcommit = true, gitrebase = true })[vim.bo.filetype] then return end
    local mark = api.nvim_buf_get_mark(0, '"')
    if mark[1] > 0 and mark[1] <= api.nvim_buf_line_count(0) then pcall(api.nvim_win_set_cursor, 0, mark) end
  end,
})

api.nvim_create_autocmd("BufEnter", {
  group = augroup,
  nested = true,
  callback = function(args)
    if vim.v.vim_did_enter == 1 then maybe_load_canola(args.buf) end
  end,
})

api.nvim_create_autocmd("VimEnter", {
  group = augroup,
  nested = true,
  callback = function() maybe_load_canola(0) end,
})

api.nvim_create_autocmd("VimResized", {
  group = augroup,
  callback = function()
    local tab = vim.fn.tabpagenr()
    vim.cmd "tabdo wincmd ="
    vim.cmd("tabnext " .. tab)
  end,
})
