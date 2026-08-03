-- pr: move between PRs, and between commits inside a PR.
--
--   <c-p>        PR list (pr://list)  ]p / [p     next / prev PR
--   :PR pick     pick a PR (fzf)      ]c / [c     next / prev commit
--   <leader>gf   files view           <leader>m   cumulative <-> incremental
--   <leader>gC   pick a commit        <leader>gA  whole-PR view
--   G            live CI pane (on pr://files)
--
-- Inside either PR buffer, the verbs (pr.verbs, same keys on both):
--   D draft <-> ready    M merge    C checkout <-> back    O browser    X close
--
-- And the fast list (pr.marks), the few PRs you are working through now:
--   A mark / unmark      ]m / [m next / prev mark      <leader>1-9 a slot
--
-- Modules:
--   pr        state + navigation + loading (this file, the orchestrator)
--   pr.data   every git/forge query, read and write
--   pr.list   the PR home surface (pr://list) - stacks render adjacent
--   pr.marks  the fast list - a few PRs, slotted, ]m / [m and <leader>1-9
--   pr.pick   the two fzf surfaces (PR list, commit list)
--   pr.verbs  the write side - one verb, both surfaces
--   pr.view   the files buffer - THE review surface
--   pr.tree   where a PR becomes real files (a worktree, never your checkout)
--   pr.ci     checks, jobs and job logs (store + pr://checks + pr://job/N)
--
-- The files view (pr.view) is the single surface: picking a PR lands there,
-- and every navigation re-renders it. From a file row, <CR> materialises the
-- PR as a worktree and opens the real file out of it (LSP, fugitive and
-- gitsigns all see the PR state, and your own tree is never touched), and
-- dd/dv opens the full diffs.nvim review.
--
-- State is five values. Every action recomputes a range and re-renders.

local data = require "pr.data"

local M = {}

---@class pr.State
local S = {
  root = nil, ---@type string?
  pr = nil, ---@type table?
  base = nil, ---@type string?
  target = nil, ---@type string?
  commits = {}, ---@type table[]
  idx = 0,
  mode = "cumulative", ---@type "cumulative"|"incremental"
}

M.state = S

local function warn(msg) vim.notify("pr: " .. msg, vim.log.levels.WARN) end
local function info(msg) vim.notify("pr: " .. msg, vim.log.levels.INFO) end

--- Open (or re-render) the files view. The one and only render entry point.
function M.render()
  if #S.commits == 0 then return warn "no PR loaded - <leader>gP first" end
  require("pr.view").open()
  -- An open CI pane re-points itself at whatever PR is loaded now, so ]p / [p
  -- carry it along. Closed, this is a no-op and pr.ci is never even required.
  local pane = package.loaded["pr.ci.pane"]
  if pane then pane.follow() end
end

--- The CI pane for the loaded PR (pr://checks). G on pr://files.
function M.checks() require("pr.ci.pane").toggle() end

M.files = M.render

--- The PR the user means right now: the row under the cursor on pr://list,
--- and otherwise whatever is loaded. Every surface-agnostic action resolves
--- its subject here - the verbs and the marks - so "which PR" is decided in
--- one place and the two can never disagree about it.
---@return string? root, table? pr
function M.target()
  local list = package.loaded["pr.list"]
  if list and vim.api.nvim_buf_get_name(0):match "pr://list$" then
    local p = list.order[vim.fn.line "."]
    if p and list.root then return list.root, p end
  end
  if S.pr and S.root then return S.root, S.pr end
end

--- Re-paint whatever surfaces are live, without touching the network. What a
--- verb that mutated a PR table in place needs, and what a mark needs after
--- changing which slot digit a row wears.
function M.repaint()
  local list = package.loaded["pr.list"]
  if list then list.repaint() end
  local view = package.loaded["pr.view"]
  if view and view.active() then view.render() end
end

-- --------------------------------------------------------------- loading ---

--- Point the whole flow at a PR (called by pr.pick with a picked entry).
function M.load(root, pr)
  local ref = data.ref(pr.number)

  local function go()
    S.root, S.pr = root, pr
    S.base = "origin/" .. pr.baseRefName
    S.target = ref
    S.commits = data.commits(root, S.base, ref)
    if #S.commits == 0 then return warn("no commits in #" .. pr.number) end
    S.idx = #S.commits -- tip: cumulative at the tip == the whole PR
    S.mode = "cumulative"
    M.render()
  end

  if data.ref_exists(root, ref) then return go() end

  info("fetching #" .. pr.number .. "...")
  data.fetch(root, function(ok, err)
    if not ok then return warn("fetch failed: " .. (err or "")) end
    if not data.ref_exists(root, ref) then
      return warn("no local ref " .. ref .. " - is the pull refspec installed? :PR refspec")
    end
    go()
  end)
end

--- Point the flow at ONE landed commit, from pr://log. The state machine is
--- the same as a PR's with a single commit in it, so every gesture on
--- pr://files works unchanged - the only absent thing is `pr`, which the
--- header renders around (see pr.view) and pr.tree keys its worktree on.
---
--- "incremental" is what a landed commit means: sha^..sha, what THIS commit
--- changed, exactly the mode `]c` produces inside a PR.
---@param commit table  a row from pr.data.log
function M.load_commit(root, commit)
  S.root, S.pr = root, nil
  S.base = commit.sha .. "^"
  S.target = commit.sha
  S.commits = { commit }
  S.idx = 1
  S.mode = "incremental"
  M.render()
end

--- Re-read the loaded PR from the remote: what `:e` and `R` mean on
--- pr://files. `:e` on a real file rereads it from disk, so on a PR buffer
--- it rereads the PR from origin - a force-push or a new commit lands here.
---
--- Renders from cache FIRST and fetches behind it: :e must never leave a
--- blank buffer sitting there while the network answers.
function M.reload()
  if #S.commits == 0 then return warn "no PR loaded - <c-p> first" end
  M.render()
  -- A landed commit is immutable: there is no remote state for a re-fetch to
  -- discover, so `:e` on one is just the re-render above.
  if not S.pr then return end
  local at = S.commits[S.idx] and S.commits[S.idx].sha
  info("refreshing #" .. S.pr.number .. "...")
  data.fetch(S.root, function(ok, err) -- clears every diff cache on the way
    if not ok then return warn("fetch failed: " .. (err or "")) end
    local commits = data.commits(S.root, S.base, S.target)
    if #commits == 0 then return warn("no commits in #" .. S.pr.number) end
    S.commits = commits
    -- Hold position on the same commit; a force-push that rewrote it drops
    -- us at the tip, which is where a rewritten PR wants reviewing anyway.
    S.idx = #commits
    for i, c in ipairs(commits) do
      if c.sha == at then S.idx = i end
    end
    M.render()
  end)
end

-- --------------------------------------------------------------- pickers ---

function M.list() require("pr.list").open() end

--- The commit log of the default branch (pr://log) - the landed counterpart
--- to pr://list's open work.
function M.log() require("pr.log").open() end

function M.pick_pr() require("pr.pick").pr() end

function M.pick_commit() require("pr.pick").commit() end

-- ------------------------------------------------------------- navigation ---

---@param delta integer
function M.step(delta)
  if #S.commits == 0 then return warn "no PR loaded - <leader>gP first" end
  local n = #S.commits
  S.idx = ((S.idx - 1 + delta) % n) + 1
  M.render()
end

--- ]p / [p: step to the adjacent PR in pr://list display order (stacks are
--- adjacent there, so this walks a stack parent-first). Wraps like M.step.
---@param delta integer
function M.step_pr(delta)
  local list = require "pr.list"
  local n = #list.order
  if n == 0 or not list.root then return warn "no PR list - <c-p> first" end
  local cur = 0
  for i, p in ipairs(list.order) do
    if S.pr and p.number == S.pr.number then
      cur = i
      break
    end
  end
  -- No current PR: ]p enters at the top, [p at the bottom.
  local nxt = cur == 0 and (delta > 0 and 1 or n) or ((cur - 1 + delta) % n) + 1
  M.load(list.root, list.order[nxt])
end

function M.toggle_mode()
  if #S.commits == 0 then return warn "no PR loaded - <leader>gP first" end
  S.mode = S.mode == "cumulative" and "incremental" or "cumulative"
  M.render()
end

--- Jump back to the whole-PR view (cumulative at the tip).
function M.whole()
  if #S.commits == 0 then return warn "no PR loaded - <leader>gP first" end
  S.idx, S.mode = #S.commits, "cumulative"
  M.render()
end

-- ------------------------------------------------------------------ setup ---

--- `:PR clean` - drop the worktrees <CR> materialised.
function M.clean() require("pr.tree").clean() end

function M.refspec()
  local root = data.root()
  if not root then return warn "not in a git repository" end
  if data.has_refspec(root) then return info "pull refspec already installed" end
  if not data.install_refspec(root) then return warn "could not write git config" end
  info "refspec installed, fetching PR refs..."
  data.fetch(root, function(ok, err)
    if ok then
      info "PR refs available - <leader>gP to pick one"
    else
      warn("fetch failed: " .. (err or ""))
    end
  end)
end

return M
