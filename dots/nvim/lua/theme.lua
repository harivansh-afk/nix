local M = {}

local xdg_state_home = vim.env.XDG_STATE_HOME or (vim.env.HOME .. "/.local/state")
local theme_state_file = xdg_state_home .. "/theme/current"

local function ensure_server_socket()
  local socket_path = ("/tmp/nvim-%d.sock"):format(vim.fn.getpid())
  local active_servers = vim.fn.serverlist()

  for _, server in ipairs(active_servers) do
    if server == socket_path then return end
  end

  local stat = vim.uv.fs_stat(socket_path)
  if stat and stat.type == "socket" then vim.fn.delete(socket_path) end

  vim.fn.serverstart(socket_path)
end

local function read_mode()
  local ok, lines = pcall(vim.fn.readfile, theme_state_file)
  if not ok or not lines or not lines[1] then return "dark" end

  local mode = vim.trim(lines[1])
  if mode == "light" then return "light" end

  return "dark"
end

function M.apply(mode)
  mode = mode or read_mode()
  local scheme = mode == "light" and "cozybox-light" or "cozybox"
  if vim.o.background == mode and vim.g.colors_name == scheme then return end

  vim.cmd.colorscheme(scheme)
  if package.loaded["nvim-web-devicons"] then require("nvim-web-devicons").refresh() end
  vim.cmd "redrawstatus!"
end

function M.setup()
  local group = vim.api.nvim_create_augroup("cozybox_theme_sync", { clear = true })

  ensure_server_socket()

  vim.api.nvim_create_autocmd({ "VimEnter", "FocusGained" }, {
    group = group,
    callback = function() M.apply() end,
  })

  vim.api.nvim_create_user_command("ThemeSync", function(opts)
    local mode = opts.args ~= "" and opts.args or nil
    M.apply(mode)
  end, {
    nargs = "?",
    complete = function() return { "dark", "light" } end,
  })

  M.apply()
end

return M
