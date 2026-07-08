-- mux: in-Neovim "multiplexer" brain. Each "view" is a tagged tabpage; untagged
-- tabpages are plain tmux-style windows. Switching projects is `:connect` to
-- another per-project nvim server (see scripts/bin/mux.sh). Bindings mirror the
-- old tmux config: <c-b> prefix, h/j/k/l panes, -/' splits, c new window,
-- [ copy mode, H/J/K/L session cycling, f picker, d detach. The tab bar is
-- hidden by default: it peeks while a prefix command is pending, and <c-b>\
-- pins/unpins it.

local core = require "mux.core"
local view = require "mux.view"
local project = require "mux.project"
local session = require "mux.session"
local line = require "mux.line"

local M = {}

M.views = core.views

M.open_view = view.open_view
M.resolve_view = view.resolve_view
M.in_view = view.in_view
M.state = view.state
M.last_view = view.last_view
M.close_view = view.close_view
M.kill_pane = view.kill_pane
M.new_window = view.new_window
M.split_terminal = view.split_terminal
M.toggle_zoom = view.toggle_zoom

M._connect = project._connect
M.pick_project = project.pick_project
M.cycle_project = project.cycle_project
M.list_entries = project.list_entries
M.last_session = project.last_session
M.stop_to_latest = project.stop_to_latest
M.kill_to_latest = project.kill_to_latest

M.stop_session = session.stop_session
M.kill_session = session.kill_session
M.reload = session.reload
M.reload_all = session.reload_all
M.save_session = session.save_session
M.load_session = session.load_session

local AUTOSAVE_INTERVAL_MS = 5 * 60 * 1000

function M.setup()
  if M._did then return end
  M._did = true

  vim.o.sessionoptions = "buffers,curdir,folds,globals,help,tabpages,winsize,winpos"
  vim.opt.fillchars:append { vert = "│" }

  local prefix = "<c-b>"

  ---@type table<string, fun()> key typed after the prefix -> mux command
  local commands = {}

  ---@param lhs string key typed after the prefix (keycode notation ok)
  ---@param rhs fun()
  ---@param desc string
  local function muxmap(lhs, rhs, desc)
    commands[vim.keycode(lhs)] = function()
      rhs()
      line.refresh()
    end
  end

  -- Bare prefix peeks the tab bar, then reads one key: a mux command if bound,
  -- else it falls through to <c-w>, so <c-b>h/j/k/l is pane navigation and any
  -- unbound <c-b>* keeps its window-command meaning. In terminal mode <c-b><c-b>
  -- sends a literal <c-b> and <c-b>[ enters copy mode.
  local fallthrough = {
    n = vim.keycode "<c-w>",
    i = vim.keycode "<c-o><c-w>",
    t = vim.keycode "<c-\\><c-n><c-w>",
  }
  local function dispatch()
    line.peek(true)
    local ok, key = pcall(vim.fn.getcharstr)
    line.peek(false)
    if not ok or key == "" or key == vim.keycode "<esc>" then return end
    local mode = vim.api.nvim_get_mode().mode:sub(1, 1)
    if mode == "t" then
      if key == vim.keycode(prefix) then
        vim.api.nvim_feedkeys(key, "n", false)
        return
      end
      if key == "[" then
        vim.api.nvim_feedkeys(vim.keycode [[<c-\><c-n>]], "n", false)
        return
      end
    end
    local command = commands[key]
    if command then
      command()
      return
    end
    vim.api.nvim_feedkeys((fallthrough[mode] or fallthrough.n) .. key, "m", false)
  end
  vim.keymap.set({ "n", "i", "t" }, prefix, dispatch, { desc = "mux: prefix" })

  -- tmux parity
  muxmap("-", function() M.split_terminal(false) end, "mux: horizontal split terminal")
  muxmap("'", function() M.split_terminal(true) end, "mux: vertical split terminal")
  muxmap("c", M.new_window, "mux: new window")
  muxmap("x", M.kill_pane, "mux: kill pane")
  muxmap("z", M.toggle_zoom, "mux: zoom pane (toggle fullscreen)")
  muxmap("n", function() vim.cmd "tabnext" end, "mux: next window")
  muxmap("p", function() vim.cmd "tabprevious" end, "mux: previous window")
  muxmap("y", function()
    core.leave_terminal()
    pcall(vim.cmd, "buffer #")
  end, "mux: previous buffer (last shell)")
  for i = 1, 9 do
    muxmap(tostring(i), function()
      local tabs = vim.api.nvim_list_tabpages()
      if tabs[i] then vim.api.nvim_set_current_tabpage(tabs[i]) end
    end, "mux: window " .. i)
  end
  for _, key in ipairs { "H", "K" } do
    muxmap(key, function() M.cycle_project(-1) end, "mux: previous session")
  end
  for _, key in ipairs { "J", "L" } do
    muxmap(key, function() M.cycle_project(1) end, "mux: next session")
  end
  muxmap("f", M.pick_project, "mux: switch project")
  muxmap("d", function() vim.cmd "detach" end, "mux: detach to shell")

  -- views + session lifecycle
  for name, spec in pairs(core.views) do
    local view_name = name
    muxmap(spec.key, function() M.open_view(view_name) end, "mux: " .. view_name)
  end
  muxmap("<tab>", M.last_session, "mux: last session")
  muxmap("<bs>", M.last_session, "mux: last session")
  muxmap("6", M.last_view, "mux: last view")
  muxmap("s", M.save_session, "mux: save session")
  muxmap("S", M.stop_to_latest, "mux: stop session (hop to last)")
  muxmap("X", M.kill_to_latest, "mux: kill session (hop to last)")
  muxmap("R", M.reload, "mux: reload session (restart)")
  muxmap([[\]], line.toggle, "mux: pin/unpin tab bar")

  local group = vim.api.nvim_create_augroup("mux", { clear = true })
  line.setup_hl()
  line.apply_visibility()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = line.setup_hl,
  })
  vim.api.nvim_create_autocmd("TabClosed", {
    group = group,
    callback = function()
      core.prune()
      line.refresh()
    end,
  })
  vim.api.nvim_create_autocmd({ "TabNew", "DirChanged", "WinNew", "WinClosed", "WinResized" }, {
    group = group,
    callback = line.refresh,
  })
  vim.api.nvim_create_autocmd("TabEnter", {
    group = group,
    callback = function()
      vim.schedule(core.restore_terminal_focus)
      line.refresh()
    end,
  })
  vim.api.nvim_create_autocmd("UIEnter", {
    group = group,
    callback = function()
      line.setup_hl()
      line.apply_visibility()
      line.refresh()
      vim.schedule(core.restore_terminal_focus)
    end,
  })

  -- tmux pane semantics: when a terminal's job exits, its pane goes with it,
  -- except in persistent task views (build/test) where the output stays.
  vim.api.nvim_create_autocmd("TermClose", {
    group = group,
    callback = function(args)
      if not vim.api.nvim_buf_is_valid(args.buf) then return end
      for _, win in ipairs(vim.fn.win_findbuf(args.buf)) do
        if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative == "" then
          local tp = vim.api.nvim_win_get_tabpage(win)
          local name = core.tab_view[tp]
          local spec = name and core.views[name]
          if not (spec and spec.lifecycle == "persistent") then view.on_terminal_exit(win, args.buf) end
        end
      end
    end,
  })
  vim.api.nvim_create_autocmd("TabLeave", {
    group = group,
    callback = function()
      view._alt = vim.api.nvim_get_current_tabpage()
      line.refresh()
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      line.stop_watchers()
      session.save_session()
      session.clear_pid()
    end,
  })

  session.record_root()
  session.record_pid()
  line.start_watchers()

  if not session.load_session() then
    vim.cmd.edit(vim.fn.getcwd())
    core.tag(vim.api.nvim_get_current_tabpage(), "edit")
  end
  line.apply_visibility()
  line.refresh()

  M._timer = vim.uv.new_timer()
  M._timer:start(AUTOSAVE_INTERVAL_MS, AUTOSAVE_INTERVAL_MS, vim.schedule_wrap(function() session.save_session() end))
end

return M
