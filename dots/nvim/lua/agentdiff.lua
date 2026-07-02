-- agentdiff: agent sessions -> worktrees -> diffs.nvim, no UI of its own.
--
-- Two entry points:
--   pick(): fzf-lua picker over every linked worktree under `roots`
--           (git-truth: `git worktree list` from each main checkout, so
--           tmpfs worktrees are included). Select -> tab, tcd, :Diff review.
--   auto(): on nvim startup, if an agent session is live (state file written
--           by the agent-session-state.sh hook), open its diff directly.
--
-- Config (vim.g.agentdiff): roots, state_dir, auto (default true),
-- active_secs (session considered live if last event is this recent).

local M = {}

local defaults = {
  roots = { "~/Documents/Git", "~/Documents/GitHub" },
  state_dir = (os.getenv "XDG_STATE_HOME" or vim.fs.normalize "~/.local/state") .. "/agent-sessions",
  auto = true,
  active_secs = 300,
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

local function base_ref(path)
  for _, ref in ipairs { "main", "master" } do
    if git(path, "rev-parse", "--verify", "--quiet", ref) then return ref end
  end
end

-- base..working-tree in one diff: committed and dirty agent work together.
local function shortstat(wt)
  wt.base = base_ref(wt.path)
  if not wt.base then return end
  local mb = git(wt.path, "merge-base", wt.base, "HEAD")
  if not (mb and mb[1]) then return end
  local stat = (git(wt.path, "diff", "--shortstat", mb[1]) or {})[1] or ""
  wt.add = tonumber(stat:match "(%d+) insertion") or 0
  wt.del = tonumber(stat:match "(%d+) deletion") or 0
end

local function age_str(ts)
  local age = os.time() - (ts or 0)
  if age < 60 then return age .. "s" end
  if age < 3600 then return math.floor(age / 60) .. "m" end
  return math.floor(age / 3600) .. "h"
end

-- Live sessions keyed by worktree path (falls back to cwd).
local function sessions()
  local by_dir, o = {}, opts()
  if not vim.uv.fs_stat(o.state_dir) then return by_dir end
  for name, kind in vim.fs.dir(o.state_dir) do
    if kind == "file" and name:match "%.json$" then
      local fd = io.open(o.state_dir .. "/" .. name)
      if fd then
        local ok, s = pcall(vim.json.decode, fd:read "*a")
        fd:close()
        if ok and type(s) == "table" then
          local key = (s.worktree and s.worktree ~= "" and s.worktree) or s.cwd
          if key and key ~= "" and (not by_dir[key] or (s.ts or 0) > (by_dir[key].ts or 0)) then by_dir[key] = s end
        end
      end
    end
  end
  return by_dir
end

local function is_active(s) return s and (os.time() - (s.ts or 0)) <= opts().active_secs end

local function collect()
  local entries, live = {}, sessions()
  for _, repo in ipairs(repos()) do
    for _, wt in ipairs(worktrees(repo)) do
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

-- Open a worktree's review: reuse its tab when one exists.
function M.open(entry)
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    if vim.fn.getcwd(-1, vim.api.nvim_tabpage_get_number(tab)) == entry.path then
      vim.api.nvim_set_current_tabpage(tab)
      return
    end
  end
  -- Reuse a fresh, empty nvim instead of leaving an empty tab behind.
  local fresh = vim.fn.argc() == 0
    and #vim.api.nvim_list_tabpages() == 1
    and vim.api.nvim_buf_get_name(0) == ""
    and not vim.bo.modified
  if not fresh then vim.cmd.tabnew() end
  vim.cmd.tcd(vim.fn.fnameescape(entry.path))
  local ok, err = pcall(vim.cmd, "Diff review " .. (entry.base or base_ref(entry.path) or ""))
  if not ok then vim.notify("agentdiff: " .. err, vim.log.levels.WARN) end
end

local C = {
  repo = "\27[34m%s\27[0m", -- blue
  add = "\27[32m%s\27[0m", -- green
  del = "\27[31m%s\27[0m", -- red
  live = "\27[33m%s\27[0m", -- yellow
  dim = "\27[90m%s\27[0m",
}

function M.pick()
  pcall(vim.cmd.packadd, "fzf-lua")
  local entries = collect()
  if #entries == 0 then
    vim.notify("agentdiff: no worktrees found", vim.log.levels.INFO)
    return
  end
  local by_path, lines = {}, {}
  for _, e in ipairs(entries) do
    shortstat(e)
    by_path[e.path] = e
    local badge = ""
    if is_active(e.session) then
      badge = C.live:format(("[%s %s]"):format(e.session.agent or "agent", age_str(e.session.ts)))
    elseif e.session then
      badge = C.dim:format "[idle]"
    end
    lines[#lines + 1] = ("%s %s %s %s %s\t%s"):format(
      C.repo:format(("%-12s"):format(e.repo)),
      ("%-28s"):format(e.branch),
      C.add:format(("+%-5d"):format(e.add or 0)),
      C.del:format(("-%-5d"):format(e.del or 0)),
      ("%-14s"):format(badge),
      C.dim:format(e.path)
    )
  end
  require("fzf-lua").fzf_exec(lines, {
    prompt = "worktrees> ",
    fzf_opts = { ["--ansi"] = true, ["--no-sort"] = true, ["--delimiter"] = "\t", ["--with-nth"] = "1" },
    actions = {
      ["default"] = function(selected)
        local path = selected[1]:match "\t(.+)$"
        if path and by_path[path] then M.open(by_path[path]) end
      end,
    },
  })
end

-- Startup: open the most recently active agent session's diff. Prefers a
-- session inside nvim's cwd (repo you opened nvim in), else the newest one.
function M.auto()
  if not opts().auto then return end
  if vim.fn.argc() > 0 then return end -- opening specific files: stay out of the way
  local cwd, best = vim.fn.getcwd(), nil
  for dir, s in pairs(sessions()) do
    if is_active(s) and s.worktree and s.worktree ~= "" then
      local in_cwd = dir:sub(1, #cwd) == cwd or cwd:sub(1, #dir) == dir
      if not best or (in_cwd and not best.in_cwd) or (in_cwd == best.in_cwd and (s.ts or 0) > best.ts) then
        best = { path = s.worktree, ts = s.ts or 0, in_cwd = in_cwd }
      end
    end
  end
  if best then M.open { path = best.path } end
end

return M
