local M = {}

---@class mux.ViewSpec
---@field key string single char appended to the prefix to open this view
---@field kind 'editor'|'vcs'|'terminal'|'task' how the tab's content is built
---@field cmd? string[] terminal command (terminal kind), defaults to `just <recipe>` for tasks
---@field restore_cmd? string[] command used instead of `cmd` when restoring a saved session
---@field recipe? string justfile recipe name (task kind)
---@field lifecycle? 'ephemeral'|'persistent' ephemeral tabs auto-close when their terminal exits
---@field restore? boolean re-materialize this view when a saved session is loaded

---@type table<string, mux.ViewSpec>
M.views = {
  edit = { key = "e", kind = "editor" },
  ai = {
    key = "a",
    kind = "terminal",
    cmd = { "claude" },
    restore_cmd = { "claude", "--continue" },
    lifecycle = "ephemeral",
    restore = true,
  },
  zsh = {
    key = "g",
    kind = "terminal",
    cmd = { vim.o.shell },
    lifecycle = "ephemeral",
  },
  vcs = { key = "v", kind = "vcs", restore = true },
  run = { key = "r", kind = "task", recipe = "run", lifecycle = "ephemeral" },
  build = { key = "b", kind = "task", recipe = "build", lifecycle = "persistent" },
  test = { key = "t", kind = "task", recipe = "test", lifecycle = "persistent" },
}

M.VIEW_ORDER = { "edit", "vcs", "ai", "run", "build", "test", "zsh" }

-- tabpage handle -> view name
---@type table<integer, string>
M.tab_view = {}

---@param tabpage integer
---@param name string
function M.tag(tabpage, name) M.tab_view[tabpage] = name end

function M.prune()
  for tp in pairs(M.tab_view) do
    if not vim.api.nvim_tabpage_is_valid(tp) then M.tab_view[tp] = nil end
  end
end

---@param name string
---@return integer? tabpage handle of the open view, or nil if none
function M.find_view(name)
  for tp, v in pairs(M.tab_view) do
    if v == name and vim.api.nvim_tabpage_is_valid(tp) then return tp end
  end
  return nil
end

---@param tp integer
---@return integer count of non-floating windows in the tabpage
function M.live_window_count(tp)
  local n = 0
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(tp)) do
    if vim.api.nvim_win_get_config(w).relative == "" then n = n + 1 end
  end
  return n
end

---@param win integer
---@return boolean true if `win` is the last non-floating window in its tabpage
function M.last_window(win) return M.live_window_count(vim.api.nvim_win_get_tabpage(win)) <= 1 end

---@param p string?
---@return string
function M.canon(p)
  if not p or p == "" then return "" end
  return (vim.fn.fnamemodify(p, ":p"):gsub("/$", ""))
end

---@return string
function M.state_dir() return vim.fn.stdpath "state" .. "/mux" end

---@return string
function M.runtime_dir()
  local base = vim.env.XDG_RUNTIME_DIR
  if not base or base == "" then
    if vim.uv.os_uname().sysname == "Darwin" then
      base = (vim.env.TMPDIR or "/tmp"):gsub("/$", "")
    else
      base = "/run/user/" .. vim.uv.getuid()
    end
  end
  return base .. "/mux"
end

---@return string dir
function M.sessions_dir() return M.state_dir() .. "/sessions" end

-- Leave terminal-mode so a stray <c-c> hits Normal mode, not the terminal.
function M.leave_terminal()
  if vim.fn.mode() == "t" then
    vim.b.term_programmatic = true
    vim.cmd.stopinsert()
  end
end

---@return boolean
function M.restore_terminal_focus()
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].buftype ~= "terminal" or not vim.b[buf].term_insert then return false end
  pcall(vim.cmd.startinsert)
  return true
end

---@param msg string
function M.log(msg)
  local file = vim.env.MUX_LOG_FILE
  if not file or file == "" then return end
  pcall(vim.fn.mkdir, vim.fn.fnamemodify(file, ":h"), "p")
  pcall(vim.fn.writefile, { ("[%s] %s"):format(os.date "%Y-%m-%dT%H:%M:%S%z", msg) }, file, "a")
end

return M
