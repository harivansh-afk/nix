-- agentdiff: dashboard mapping live agent sessions -> worktrees -> diffs.nvim.
--
-- Discovery is git-truth: every repo under `roots` is asked for its linked
-- worktrees (`git worktree list`), which includes tmpfs worktrees since git
-- registers them in the main checkout's .git/worktrees. Liveness comes from
-- the state files written by the agent-session-state.sh hook. Pokes arrive
-- over an RPC socket (see plugin/agentdiff.lua) and only add latency sugar;
-- a missed poke costs nothing because refresh rebuilds from disk.
--
-- <CR> on an entry: new tab, tab-local cd into the worktree, `:Diff review
-- <base>` (diffs.nvim full-repo review of committed + dirty vs merge-base).

local M = {}

local defaults = {
  roots = { "~/Documents/Git", "~/Documents/GitHub" },
  state_dir = (os.getenv "XDG_STATE_HOME" or vim.fs.normalize "~/.local/state") .. "/agent-sessions",
  push = false, -- auto-open a tab when an agent touches a not-yet-open worktree
  active_secs = 120, -- session shown [active] if its last event is this recent
}

local function opts() return vim.tbl_deep_extend("force", defaults, vim.g.agentdiff or {}) end

local function git(dir, ...)
  local out = vim.fn.systemlist { "git", "-C", dir, ... }
  if vim.v.shell_error ~= 0 then return nil end
  return out
end

local function repos()
  local found = {}
  for _, root in ipairs(opts().roots) do
    root = vim.fs.normalize(root)
    if vim.uv.fs_stat(root) then
      for name, kind in vim.fs.dir(root) do
        local path = root .. "/" .. name
        if kind == "directory" and vim.uv.fs_stat(path .. "/.git") then found[#found + 1] = path end
      end
    end
  end
  return found
end

-- Linked worktrees of a repo, main checkout (first porcelain block) skipped.
local function worktrees(repo)
  local out = git(repo, "worktree", "list", "--porcelain") or {}
  local wts, cur, first = {}, nil, true
  for _, line in ipairs(out) do
    local path = line:match "^worktree (.+)$"
    if path then
      if first then
        first = false
      else
        cur = { repo = vim.fs.basename(repo), path = path, branch = "?" }
        wts[#wts + 1] = cur
      end
    elseif cur then
      local branch = line:match "^branch refs/heads/(.+)$"
      if branch then cur.branch = branch end
      if line == "detached" then cur.branch = "(detached)" end
    end
  end
  return wts
end

local function base_ref(wt)
  for _, ref in ipairs { "main", "master" } do
    if git(wt.path, "rev-parse", "--verify", "--quiet", ref) then return ref end
  end
end

local function shortstat(wt)
  wt.base = base_ref(wt)
  if not wt.base then return end
  local mb = git(wt.path, "merge-base", wt.base, "HEAD")
  if not (mb and mb[1]) then return end
  -- base..working-tree in one diff: committed and dirty agent work together
  local out = git(wt.path, "diff", "--shortstat", mb[1])
  local stat = out and out[1] or ""
  wt.add = tonumber(stat:match "(%d+) insertion") or 0
  wt.del = tonumber(stat:match "(%d+) deletion") or 0
end

local function sessions()
  local by_dir, o = {}, opts()
  for name, kind in vim.fs.dir(o.state_dir) do
    if kind == "file" and name:match "%.json$" then
      local fd = io.open(o.state_dir .. "/" .. name)
      if fd then
        local ok, s = pcall(vim.json.decode, fd:read "*a")
        fd:close()
        if ok and type(s) == "table" then
          local key = (s.worktree ~= "" and s.worktree) or s.cwd
          if key and key ~= "" then by_dir[key] = s end
        end
      end
    end
  end
  return by_dir
end

local function collect()
  local entries, live = {}, sessions()
  for _, repo in ipairs(repos()) do
    for _, wt in ipairs(worktrees(repo)) do
      shortstat(wt)
      wt.session = live[wt.path]
      entries[#entries + 1] = wt
    end
  end
  table.sort(entries, function(a, b)
    local at, bt = a.session and a.session.ts or 0, b.session and b.session.ts or 0
    if at ~= bt then return at > bt end
    return a.path < b.path
  end)
  return entries
end

local function badge(s)
  if not s then return "" end
  local age = os.time() - (s.ts or 0)
  local state = (age <= opts().active_secs and s.event ~= "Stop") and "active" or "idle"
  return string.format("[%s %s %ds]", s.agent or "agent", state, age)
end

local buf

local function render()
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then return end
  local entries = collect()
  local lines = {}
  for _, e in ipairs(entries) do
    lines[#lines + 1] = string.format(
      "%-14s %-28s +%-5d -%-5d %-24s %s",
      e.repo, e.branch, e.add or 0, e.del or 0, badge(e.session), e.path
    )
  end
  if #lines == 0 then lines = { "no worktrees found" } end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.b[buf].agentdiff_entries = entries
end

local function tab_for(path)
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    if vim.fn.getcwd(-1, vim.api.nvim_tabpage_get_number(tab)) == path then return tab end
  end
end

function M.enter(entry)
  local existing = tab_for(entry.path)
  if existing then
    vim.api.nvim_set_current_tabpage(existing)
    return
  end
  vim.cmd.tabnew()
  vim.cmd.tcd(vim.fn.fnameescape(entry.path))
  local ok, err = pcall(vim.cmd, "Diff review " .. (entry.base or ""))
  if not ok then vim.notify("agentdiff: " .. err, vim.log.levels.WARN) end
end

function M.open()
  if buf and vim.api.nvim_buf_is_valid(buf) then
    local win = vim.fn.bufwinid(buf)
    if win ~= -1 then
      vim.api.nvim_set_current_win(win)
    else
      vim.cmd("botright sbuffer " .. buf)
    end
  else
    vim.cmd "botright new"
    buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_name(buf, "agentdiff://dashboard")
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "hide"
    vim.bo[buf].swapfile = false
    local function entry_at_cursor()
      local entries = vim.b[buf].agentdiff_entries or {}
      return entries[vim.api.nvim_win_get_cursor(0)[1]]
    end
    vim.keymap.set("n", "<cr>", function()
      local e = entry_at_cursor()
      if e then M.enter(e) end
    end, { buffer = buf, silent = true })
    vim.keymap.set("n", "r", render, { buffer = buf, silent = true })
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, silent = true })
  end
  render()
end

-- Debounced entry point for hook pokes (remote-expr). `worktree` is the
-- directory the agent just touched ("" on session end).
local timer
function M.poke(worktree)
  local o = opts()
  if timer then timer:stop() end
  timer = vim.defer_fn(function()
    render()
    if o.push and worktree and worktree ~= "" and not tab_for(worktree) then
      for _, e in ipairs(collect()) do
        if e.path == worktree then
          M.enter(e)
          break
        end
      end
    end
  end, 300)
  return "ok"
end

return M
