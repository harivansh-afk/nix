local core = require "mux.core"
local project = require "mux.project"
local session = require "mux.session"
local view = require "mux.view"

local M = {}

local canon = core.canon
local find_view = core.find_view
local views = core.views
local VIEW_ORDER = core.VIEW_ORDER
local TABLINE_EXPR = "%!v:lua.require'mux.line'.render()"
local refresh_pending = false

local function visibility_file() return core.runtime_dir() .. "/bar" end

local function visibility_mode()
  local file = visibility_file()
  if vim.fn.filereadable(file) == 1 then
    local mode = vim.fn.readfile(file)[1]
    if mode == "hide" then return "hide" end
  end
  return "show"
end

local function write_visibility(mode)
  pcall(vim.fn.mkdir, core.runtime_dir(), "p")
  pcall(vim.fn.writefile, { mode }, visibility_file())
end

---@param group string
---@param text string
---@return string
local function hl(group, text)
  if text == "" then return "" end
  return ("%%#%s#%s%%*"):format(group, text)
end

---@param current boolean
---@return string
local function label_group(current) return current and "TabLineSel" or "TabLine" end

---@param current boolean
---@param last boolean
---@return string
local function mark(current, last)
  if current then return "*" end
  if last then return "-" end
  return ""
end

---@param m string
---@param key string
---@param name string
---@param current boolean
---@return string
local function view_segment(m, key, name, current)
  local group = label_group(current)
  return table.concat {
    hl("Directory", m),
    hl(group, key),
    hl("Directory", ":"),
    hl(group, name),
  }
end

---@param m string
---@param name string
---@param current boolean
---@return string
local function session_segment(m, name, current) return hl("Directory", m) .. hl(label_group(current), name) end

---@param entries { cwd: string, socket: string, status: string }[]
---@param current string
---@return string?
local function last_session(entries, current)
  local live = {}
  for _, entry in ipairs(entries) do
    if entry.status == "live" then live[canon(entry.cwd)] = true end
  end
  local history = core.state_dir() .. "/history"
  if vim.fn.filereadable(history) ~= 1 then return nil end
  local lines = vim.fn.readfile(history)
  for i = #lines, 1, -1 do
    local root = canon(lines[i])
    if root ~= "" and root ~= current and live[root] then return root end
  end
end

---@param tp integer
---@return string label like tmux automatic-rename: basename of the tab's cwd
local function window_label(tp)
  local win = vim.api.nvim_tabpage_get_win(tp)
  local name = ""
  local ok, cwd = pcall(vim.fn.getcwd, vim.api.nvim_win_get_number(win), vim.api.nvim_tabpage_get_number(tp))
  if ok and cwd and cwd ~= "" then name = vim.fn.fnamemodify(cwd, ":t") end
  if name == "" then name = "term" end
  return name
end

---@return string[]
local function view_segments()
  core.prune()
  local current = vim.api.nvim_get_current_tabpage()
  local last = view._alt
  local parts = {}
  for _, name in ipairs(VIEW_ORDER) do
    local tp = find_view(name)
    if tp then
      local spec = views[name]
      parts[#parts + 1] = view_segment(mark(tp == current, tp == last), spec.key, name, tp == current)
    end
  end
  for _, tp in ipairs(vim.api.nvim_list_tabpages()) do
    if not core.tab_view[tp] then
      parts[#parts + 1] = view_segment(
        mark(tp == current, tp == last),
        tostring(vim.api.nvim_tabpage_get_number(tp)),
        window_label(tp),
        tp == current
      )
    end
  end
  return parts
end

---@return string[]
local function session_segments()
  local entries = project.list_entries()
  local current = session.root()
  local last = last_session(entries, current)
  local parts = {}
  for _, entry in ipairs(entries) do
    if entry.status == "live" then
      local root = canon(entry.cwd)
      local name = vim.fn.fnamemodify(root, ":t")
      if name ~= "" then parts[#parts + 1] = session_segment(mark(root == current, root == last), name, root == current) end
    end
  end
  return parts
end

function M.apply_visibility()
  if vim.env.MUX ~= "1" then return end
  if vim.o.tabline ~= TABLINE_EXPR then vim.o.tabline = TABLINE_EXPR end
  vim.o.showtabline = visibility_mode() == "hide" and 0 or 2
end

---@return string
function M.render()
  if vim.env.MUX ~= "1" then return "" end
  local ok, rendered = pcall(
    function() return (" %s%%=%s "):format(table.concat(view_segments(), " "), table.concat(session_segments(), " ")) end
  )
  if ok then return rendered end
  return ""
end

function M.refresh()
  if vim.in_fast_event() then
    vim.schedule(M.refresh)
    return
  end
  if vim.env.MUX ~= "1" or refresh_pending then return end
  refresh_pending = true
  vim.schedule(function()
    refresh_pending = false
    M.apply_visibility()
    pcall(vim.cmd.redrawtabline)
    pcall(vim.cmd.redrawstatus)
  end)
end

function M.toggle()
  if vim.env.MUX ~= "1" then return end
  write_visibility(vim.o.showtabline == 0 and "show" or "hide")
  M.apply_visibility()
  M.refresh()
end

function M.start_watchers()
  if vim.env.MUX ~= "1" or M._timer then return end
  M._timer = vim.uv.new_timer()
  M._timer:start(
    500,
    500,
    vim.schedule_wrap(function() M.refresh() end)
  )
end

function M.stop_watchers()
  local timer = M._timer
  M._timer = nil
  if timer then
    pcall(timer.stop, timer)
    pcall(timer.close, timer)
  end
end

return M
