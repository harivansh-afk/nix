-- pr.tree: the working-tree half of the flow - where a PR becomes real files.
--
-- Every other module here reads REFS. A PR's diff is computed from
-- origin/pr/N without touching your checkout, which is what makes reviewing
-- free: it never disturbs what you were doing. It is also the limit of that
-- approach, because a ref is not a file. Nothing that needs a real file on
-- disk works against one - not an LSP (rust-analyzer indexes a cargo
-- workspace, not a blob), not fugitive, not gitsigns.
--
-- So <CR> on a file row materialises the PR as a git WORKTREE and opens the
-- real file out of it. rust-analyzer, fugitive and gitsigns then see the PR
-- exactly as its author does - the thing itself, not a rendering of it.
--
-- A worktree and not a checkout, which is the whole point: your own tree is
-- never touched, so reviewing works mid-edit, on a dirty tree, without
-- stashing, and HEAD stays where you left it. `.worktrees/pr-<N>` is the same
-- repo-local convention (and the same gitignore entry) everything else here
-- uses.
--
-- Always DETACHED at the commit under review. Reviewing is reading, and there
-- is no branch named "commit 3 of 5". The division of labour is deliberate:
--   <CR>  read the PR at this commit   -> worktree, detached, never disturbs you
--   C     work on the PR               -> your tree, real branch, upstream set
--
-- Worktrees are cheap but not free, so `:PR clean` removes them.
--
-- NOT re-pointed at the PR's base for gitsigns, deliberately: in the worktree
-- HEAD *is* the PR commit, so the gutter is empty, and the obvious fix does not
-- work. gitsigns.change_base is a no-op in this version - measured against
-- `git diff --numstat` ground truth, 0 hunks for a +30/-18 file, in BOTH the
-- buffer-local and global forms and in the main checkout as well as a worktree,
-- so it is upstream and not about worktrees. The PR's diff is one command away
-- inside the worktree anyway (`:Git diff <base>...HEAD`), and pr://files is
-- already showing it. Revisit if gitsigns fixes change_base.

local data = require "pr.data"

local M = {}

local function warn(msg) vim.notify("pr: " .. msg, vim.log.levels.WARN) end
local function info(msg) vim.notify("pr: " .. msg, vim.log.levels.INFO) end

local function state() return require("pr").state end

-- ----------------------------------------------------------------- where ---

--- The worktree for a PR number. Repo-local `.worktrees/<topic>`, already
--- gitignored, so a materialised PR never shows up as untracked noise.
---@return string
function M.path_for(root, number) return root .. "/.worktrees/pr-" .. number end

--- The worktree for the loaded PR, or nil when no PR is loaded.
---@return string?
function M.path()
  local s = state()
  if not (s.root and s.pr) then return nil end
  return M.path_for(s.root, s.pr.number)
end

--- Is the PR already materialised at the commit under review? The common case
--- on a second <CR>, and it costs one rev-parse and no worktree work.
function M.at()
  local s = state()
  local c = s.commits[s.idx]
  local wt = M.path()
  if not (c and wt) or not vim.uv.fs_stat(wt) then return false end
  -- Short shas compare directly: `log --format=%h` and `rev-parse --short`
  -- both abbreviate through core.abbrev, so the same commit is the same
  -- string. Were that ever to stop holding, the answer degrades to false and
  -- the caller re-checkouts a commit it is already on - wasteful, never wrong.
  return data.head(wt).sha == c.sha
end

-- -------------------------------------------------------------- ensure ---

--- Materialise the PR at the commit under review, then run cb. Three states:
--- no worktree yet (create it), one sitting at another commit (move it), or
--- one already right here (the common case - straight through, no git work).
---@param cb fun(wt: string)  the worktree root, once it really is at that commit
function M.ensure(cb)
  local s = state()
  local c = s.commits[s.idx]
  if not (s.root and c and s.pr) then return warn "no PR loaded - <c-p> first" end
  local wt = M.path()

  if M.at() then return cb(wt) end

  ---@param moved boolean the worktree already existed and was checked out anew
  local function done(moved)
    return function(ok, err)
      if not ok then return warn("worktree failed: " .. (err or "")) end
      -- A moved worktree changed the file content under every buffer already
      -- open from it. :checktime rereads each unmodified one, so walking
      -- ]c then <CR> can never leave the previous commit's text on screen.
      if moved then pcall(vim.cmd, "silent! checktime") end
      cb(wt)
    end
  end

  if not vim.uv.fs_stat(wt) then
    info(("materialising #%d @ %s..."):format(s.pr.number, c.sha))
    return data.worktree_add(s.root, wt, c.sha, done(false))
  end

  -- An existing worktree gets MOVED to the reviewed commit rather than
  -- recreated. Edits made in there are the one thing that blocks it - the
  -- guard is on the worktree's own tree, never on yours.
  if data.dirty(wt) then
    return warn(("%s has changes - :PR clean, or commit them"):format(vim.fn.fnamemodify(wt, ":~")))
  end
  info(("moving #%d to %s..."):format(s.pr.number, c.sha))
  data.detach(wt, c.sha, done(true))
end

-- ----------------------------------------------------------------- open ---

--- <CR> on a file row: the PR's real file, at the PR's state, at this line.
---@param path string repo-relative, the POST-image path (renames included)
---@param lnum? integer new-side line to land on
function M.open(path, lnum)
  M.ensure(function(wt)
    local full = wt .. "/" .. path
    -- A file the PR DELETED has no state to open. Say so, and point at the
    -- gesture that does have something to show.
    if not vim.uv.fs_stat(full) then return warn(path .. " is not in the tree here - dd for its diff") end
    vim.cmd.edit(vim.fn.fnameescape(full))
    if lnum then
      pcall(vim.api.nvim_win_set_cursor, 0, { math.min(lnum, vim.api.nvim_buf_line_count(0)), 0 })
      vim.cmd "silent! normal! zvzz"
    end
  end)
end

-- ---------------------------------------------------------------- clean ---

--- Wipe every buffer living under `dir`. Pulling a worktree out from under an
--- open buffer orphans it (E211 the next time anything touches the file) and
--- leaves gitsigns polling a git dir that no longer exists, which surfaces as
--- an async traceback out of its update loop. So the buffers go first and the
--- directory second.
local function wipe_under(dir)
  local prefix = dir .. "/"
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(b)
    if name ~= "" and vim.startswith(name, prefix) then pcall(vim.api.nvim_buf_delete, b, { force = true }) end
  end
end

--- `:PR clean` - drop every PR worktree. They are disposable by construction
--- (detached, never edited in the normal flow), so this asks nothing and takes
--- nothing with it. A worktree carrying real changes is reported and kept.
function M.clean()
  local root = data.root()
  if not root then return warn "not in a git repository" end
  local found = {}
  for _, wt in ipairs(data.worktree_list(root)) do
    if wt:match "/%.worktrees/pr%-%d+$" then found[#found + 1] = wt end
  end
  if #found == 0 then
    data.worktree_prune(root)
    return info "no PR worktrees"
  end

  -- Synchronous: removing a worktree is a local directory unlink plus a line
  -- out of .git/worktrees, with no network anywhere near it. Async here would
  -- buy nothing and cost the ability to just report the result.
  local removed, kept = {}, {}
  for _, wt in ipairs(found) do
    local name = vim.fn.fnamemodify(wt, ":t")
    if data.dirty(wt) then
      kept[#kept + 1] = name
    else
      wipe_under(wt)
      if data.worktree_remove(root, wt) then
        removed[#removed + 1] = name
      else
        kept[#kept + 1] = name
      end
    end
  end
  data.worktree_prune(root)

  local msg = #removed > 0 and ("removed " .. table.concat(removed, ", ")) or "removed nothing"
  if #kept > 0 then msg = msg .. "; kept " .. table.concat(kept, ", ") .. " (has changes)" end
  info(msg)
end

return M
