local M = {}

local xdg_state_home = vim.env.XDG_STATE_HOME or (vim.env.HOME .. "/.local/state")
local theme_state_file = xdg_state_home .. "/theme/current"
local active_schemes = {
  cozybox = true,
  ["cozybox-light"] = true,
}

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

local function apply_cozybox_overrides()
  local links = {
    { "DiffsAdd", "DiffAdd" },
    { "DiffsDelete", "DiffDelete" },
    { "DiffsChange", "DiffChange" },
    { "DiffsText", "DiffText" },
    { "DiffsClear", "Normal" },
  }

  for _, pair in ipairs(links) do
    vim.api.nvim_set_hl(0, pair[1], { link = pair[2], default = false })
  end
end

local function read_mode()
  local ok, lines = pcall(vim.fn.readfile, theme_state_file)
  if not ok or not lines or not lines[1] then return "dark" end

  local mode = vim.trim(lines[1])
  if mode == "light" then return "light" end

  return "dark"
end

local function colorscheme_for_mode(mode)
  if mode == "light" then return "cozybox-light" end

  return "cozybox"
end

function M.statusline_label()
  local mode = vim.g.cozybox_theme_mode or read_mode()
  local scheme = vim.g.colors_name or colorscheme_for_mode(mode)
  local expected_scheme = colorscheme_for_mode(mode)

  if scheme == expected_scheme then return "theme:" .. mode end

  return ("theme:%s/%s"):format(mode, scheme)
end

function M.apply(mode)
  local next_mode = mode or read_mode()
  local next_scheme = colorscheme_for_mode(next_mode)

  if vim.o.background ~= next_mode then vim.o.background = next_mode end

  if vim.g.cozybox_theme_mode ~= next_mode or vim.g.colors_name ~= next_scheme then vim.cmd.colorscheme(next_scheme) end

  vim.g.cozybox_theme_mode = next_mode
  apply_cozybox_overrides()
  local ok_reload, fzf_reload = pcall(require, "config.fzf_reload")
  if ok_reload then pcall(fzf_reload.reload) end
  vim.schedule(function()
    local ok, lualine = pcall(require, "lualine")
    if ok then pcall(lualine.refresh, { place = { "statusline" } }) end
    pcall(vim.cmd, "redraw!")
  end)
end

function M.setup()
  local group = vim.api.nvim_create_augroup("cozybox_theme_sync", { clear = true })

  ensure_server_socket()

  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      if active_schemes[vim.g.colors_name] then apply_cozybox_overrides() end
    end,
  })

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
