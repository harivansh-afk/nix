-- pr.data: every git/gh query behind the PR review flow.
-- Diff content always comes from LOCAL refs (see refspec below), never the network.
-- `gh` is used only for PR metadata (titles, authors, base branch) and for
-- the write verbs at the bottom of this file (draft, merge, close, checkout).
--
-- Checks, jobs and job logs are NOT here: they live in pr.ci.api, which is
-- the one place that speaks to a forge's Actions API.

local M = {}

local REFSPEC = "+refs/pull/*/head:refs/remotes/origin/pr/*"

--- Gitea/Forgejo has no draft FLAG: a draft PR is literally one whose title
--- carries a WIP prefix (repository.pull-request.work_in_progress_prefixes,
--- these two by default). So on tea, "toggle draft" is a title edit - the
--- prefix is stripped for display in M.prs and re-added in M.set_draft.
local WIP_PREFIXES = { "WIP:", "[WIP]" }
local WIP = "WIP: "

---@return string title, boolean draft
local function strip_wip(title)
  for _, p in ipairs(WIP_PREFIXES) do
    if (title or ""):sub(1, #p) == p then return vim.trim(title:sub(#p + 1)), true end
  end
  return title or "", false
end

-- ---------------------------------------------------------------- running ---
-- All process plumbing lives in pr.run - one engine for this file, pr.ci.api
-- and anyone else who forks a subprocess. What stays here is the DOMAIN: the
-- diff between two commits is immutable, so every cached slot is keyed on
-- RESOLVED shas (never ref names); when origin/<base> or origin/pr/N moves,
-- new shas mean new keys and stale entries are simply never hit again -
-- invalidation is structural, not bookkeeping. M.fetch clears outright, the
-- one place this plugin moves refs.

local run = require "pr.run"
local git, spawn, await = run.git, run.spawn, run.await

function M.clear_cache() run.clear() end

---@return string? root
function M.root()
  local out = git { "rev-parse", "--show-toplevel" }
  return out and vim.trim(out[1] or "") or nil
end

--- Is the pull-ref refspec configured on origin? Without it there are no
--- local `origin/pr/N` refs and nothing else here works.
function M.has_refspec(root)
  local out = git { "-C", root, "config", "--get-all", "remote.origin.fetch" } or {}
  for _, line in ipairs(out) do
    if line:find "refs/pull/%*/head" then return true end
  end
  return false
end

function M.install_refspec(root) return git { "-C", root, "config", "--add", "remote.origin.fetch", REFSPEC } ~= nil end

---@param cb fun(ok: boolean, err?: string)
function M.fetch(root, cb)
  vim.system({ "git", "-C", root, "fetch", "origin", "--prune" }, { text = true }, function(r)
    vim.schedule(function()
      M.clear_cache()
      cb(r.code == 0, r.stderr)
    end)
  end)
end

--- Fast-forward the current branch from origin: what `:e` means on pr://log.
--- The log is of HEAD, so a PR merged in the browser only appears once HEAD
--- itself moves - a fetch alone updates origin/* and changes nothing on
--- screen. --ff-only because a surface refresh must never CREATE history: a
--- diverged branch fails loudly instead of minting a merge commit, and a
--- dirty tree that conflicts with the incoming files is git's refusal to
--- surface, not ours to guess at.
---@param cb fun(ok: boolean, err?: string)
function M.pull(root, cb)
  vim.system({ "git", "-C", root, "pull", "--ff-only", "--prune" }, { text = true }, function(r)
    vim.schedule(function()
      M.clear_cache()
      cb(r.code == 0, vim.trim(r.stderr or ""))
    end)
  end)
end

--- Ref -> sha, THE cache-key ingredient. One call per render buys automatic
--- invalidation when a ref moves outside this plugin (fetch in a terminal).
---
--- `full` asks for the whole 40 chars: forge APIs match a head sha exactly
--- (Forgejo's ?head_sha= filter does), so pr.ci needs the long form even
--- though every cache key here is happier short.
function M.resolve(root, ref, full)
  local out = git { "-C", root, "rev-parse", full and "--verify" or "--short", ref }
  return out and out[1] or ref
end

--- Local ref for a PR number. Exists only after `M.fetch` with the refspec set.
function M.ref(num) return "origin/pr/" .. num end

function M.ref_exists(root, ref)
  return git { "-C", root, "rev-parse", "--verify", "--quiet", ref .. "^{commit}" } ~= nil
end

--- Which CLI speaks for origin: gh for github.com, tea for everything else
--- (Forgejo/Gitea; tea resolves its login from the remote on its own).
---@return "gh"|"tea"
function M.forge(root)
  local out = git { "-C", root, "remote", "get-url", "origin" }
  local url = out and out[1] or ""
  return url:find "github%.com" and "gh" or "tea"
end

--- Runs a forge list command async and hands the decoded JSON rows to cb.
---@param cb fun(rows?: table[], err?: string)
local function forge_json(cmd, root, forge, cb)
  vim.system(cmd, { cwd = root, text = true }, function(r)
    vim.schedule(function()
      if r.code ~= 0 then return cb(nil, vim.trim(r.stderr or (forge .. " failed"))) end
      local ok, decoded = pcall(vim.json.decode, r.stdout)
      if not ok or type(decoded) ~= "table" then return cb(nil, "could not parse " .. forge .. " output") end
      cb(decoded)
    end)
  end)
end

--- Host part of origin's URL, for matching a tea login to THIS remote.
---@return string? host
local function origin_host(root)
  local out = git { "-C", root, "remote", "get-url", "origin" }
  local url = (out and out[1] or ""):gsub("^%w+://", ""):gsub("^[^@/]+@", "")
  local host = url:match "^([^/:]+)"
  return host ~= "" and host or nil
end

--- Session cache for M.me, keyed on origin host: `false` records a failed
--- lookup so it is not retried on every toggle.
local me_cache = {} ---@type table<string, string|false>

--- The forge login that is "me" against this repo's origin - what the
--- pr://list mine-filter compares authors to. tea answers from its local
--- login store (`tea whoami` has no JSON output and renders markdown, so the
--- login LIST is matched against origin's host instead - no network); gh has
--- no local equivalent, so it costs one `gh api user` call, once per session.
---@param cb fun(login?: string)
function M.me(root, cb)
  local host = origin_host(root)
  if not host then return cb(nil) end
  local hit = me_cache[host]
  if hit ~= nil then return cb(hit or nil) end
  local function finish(login)
    me_cache[host] = login or false
    cb(login)
  end
  if M.forge(root) == "gh" then
    return forge_json({ "gh", "api", "user" }, root, "gh", function(d) finish(d and d.login) end)
  end
  forge_json({ "tea", "login", "list", "--output", "json" }, root, "tea", function(rows)
    if not rows then return finish(nil) end
    local fallback
    for _, l in ipairs(rows) do
      if l.ssh_host == host or (l.url or ""):find(host, 1, true) then return finish(l.user) end
      if l.default == "true" then fallback = l.user end
    end
    finish(fallback)
  end)
end

--- PR list, forge-agnostic. Metadata only - async, never blocks the UI.
--- Deliberately NO CI here: the status rollup is the slow half of the list
--- call (measured: gh on neovim/neovim 0.8s bare -> 11s + HTTP 504 with
--- statusCheckRollup). Every CI query lives in pr.ci.api instead, and
--- pr.list lights the orbs from the pr.ci store behind this render.
--- Results are normalized to the gh shape:
---   { number, title, author = { login }, baseRefName, headRefName,
---     isDraft, updatedAt }
---@param cb fun(prs?: table[], err?: string)
function M.prs(root, cb)
  local forge = M.forge(root)
  local cmd
  if forge == "gh" then
    cmd = {
      "gh",
      "pr",
      "list",
      "--limit",
      "100",
      "--json",
      "number,title,author,baseRefName,headRefName,isDraft,updatedAt",
    }
  else
    cmd = {
      "tea",
      "pr",
      "list",
      "--output",
      "json",
      "--limit",
      "100",
      "--fields",
      "index,title,author,base,head,updated",
    }
  end

  forge_json(cmd, root, forge, function(decoded, err)
    if not decoded then return cb(nil, err) end
    if forge == "gh" then return cb(decoded) end

    -- Normalize tea: index is a string, drafts are the WIP: title
    -- convention, `base` is the target branch. The WIP prefix is display
    -- noise once isDraft carries it (and set_draft rebuilds it), so `title`
    -- here is always the bare title on BOTH forges.
    local prs = {}
    for _, p in ipairs(decoded) do
      local title, draft = strip_wip(p.title)
      prs[#prs + 1] = {
        number = tonumber(p.index),
        title = title,
        author = { login = p.author or "?" },
        baseRefName = p.base and p.base ~= "" and p.base or "main",
        headRefName = p.head,
        isDraft = draft,
        updatedAt = p.updated,
      }
    end
    cb(prs)
  end)
end

--- The one `git log` line this plugin reads, and its parser: a commit from a
--- PR range and a commit from a branch log are the SAME table, and every
--- consumer downstream works on either without knowing which.
--- `sha` is the short display form; `full` exists because forge APIs
--- filter on the EXACT sha string (Forgejo's ?head_sha= does) and must never
--- be handed an abbreviation. `ago` is git's own relative string ("24 hours
--- ago"), which the fzf commit picker shows in full; `ts` is the same instant
--- as unix seconds for the four-cell age column (pr.fmt.since).
local LOG_FORMAT = "--format=%h\t%H\t%an\t%ar\t%at\t%s"

---@return table[] commits  { sha, full, author, ago, ts, subject }
local function parse_log(out)
  local commits = {}
  for _, line in ipairs(out or {}) do
    local sha, full, an, ar, at, subject = line:match "^(%S+)\t(%S+)\t(.-)\t(.-)\t(%d*)\t(.*)$"
    if sha then
      commits[#commits + 1] = { sha = sha, full = full, author = an, ago = ar, ts = tonumber(at), subject = subject }
    end
  end
  return commits
end

--- Commits of a PR, OLDEST FIRST so index 1 is the first commit authored
--- (matches GitHub's Commits tab, and makes `]c` walk toward the tip).
---@return table[] commits  { sha, author, ago, subject }
function M.commits(root, base, target)
  return parse_log(git { "-C", root, "log", "--reverse", LOG_FORMAT, base .. ".." .. target })
end

--- The latest commits on a ref, NEWEST FIRST - the reading order of a log,
--- and deliberately the opposite of M.commits, which is oldest-first because
--- `]c` walks a PR toward its tip. Same row shape either way.
---@param ref string  branch, tag, or any rev
---@param n integer
---@return table[] commits
function M.log(root, ref, n) return parse_log(git { "-C", root, "log", "--max-count=" .. n, LOG_FORMAT, ref }) end

--- Every PR head sha this repo knows locally, in ONE git call. The pull
--- refspec keeps refs/remotes/origin/pr/N current, so this is how pr://list
--- gets a sha per PR without a network round trip per row. A PR opened since
--- the last fetch is simply absent - the caller decides whether that is
--- worth a fetch.
---@return table<integer, string> number -> full sha
function M.pr_heads(root)
  -- A space separator, NOT %00: vim.fn.systemlist replaces NUL bytes with
  -- SOH (:help system()), so a %00 field split silently never matches.
  local out = git { "-C", root, "for-each-ref", "--format=%(refname) %(objectname)", "refs/remotes/origin/pr" } or {}
  local map = {}
  for _, line in ipairs(out) do
    local n, sha = line:match "^refs/remotes/origin/pr/(%d+) (%x+)$"
    if n then map[tonumber(n)] = sha end
  end
  return map
end

--- The two things `]c` can mean. This is the core semantic of the whole flow.
---   cumulative  -> the PR AS OF this commit   (base...sha, merge-base)
---   incremental -> what THIS commit changed   (sha^..sha, direct)
---@return table spec  ready for require("diffs.commands").review()
function M.spec(root, base, sha, mode)
  if mode == "incremental" then return { repo = root, base = sha .. "^", target = sha, mode = "direct" } end
  return { repo = root, base = base, target = sha, mode = "merge-base" }
end

---@return string[] range args for git diff
local function range_of(mode, base, sha)
  if mode == "incremental" then return { sha .. "^", sha } end
  return { base .. "..." .. sha }
end

---@return string cache key for `kind` over a resolved range
local function key_of(kind, root, base, sha, mode, base_sha)
  return table.concat({ kind, root, mode, mode == "incremental" and sha or (base_sha or base), sha }, "\0")
end

local function files_args(root, mode, base, sha)
  return vim.list_extend({ "-C", root, "diff", "--raw", "--numstat", "-M" }, range_of(mode, base, sha))
end

local function diff_args(root, mode, base, sha)
  return vim.list_extend({ "-C", root, "diff", "--no-color", "--no-ext-diff", "-M" }, range_of(mode, base, sha))
end

--- `--raw --numstat` TOGETHER: git emits every raw record, then every
--- numstat record, in identical file order - one process answers status
--- letters, rename paths and +/- counts (was two sequential git calls).
--- Raw:     :100644 100644 abc1234 def5678 M\tpath[\tnew_path]
--- Numstat: add\tdel\tpath  (counts read by index; "-" marks binary)
---@return table[] files  { status, path, old_path?, add, del, binary }
local function parse_files(lines)
  local raw, num = {}, {}
  for _, line in ipairs(lines) do
    if line:sub(1, 1) == ":" then
      raw[#raw + 1] = line
    else
      num[#num + 1] = line
    end
  end
  local files = {}
  for i, line in ipairs(raw) do
    local letter, rest = line:match "^:%S+ %S+ %S+ %S+ (%a)%d*\t(.+)$"
    if letter then
      local old_path, path = rest:match "^(.+)\t(.+)$" -- rename/copy: old<TAB>new
      if not path then path = rest end
      local add, del = (num[i] or ""):match "^(%S+)\t(%S+)\t"
      files[#files + 1] = {
        status = letter,
        path = path,
        old_path = old_path,
        add = tonumber(add) or 0,
        del = tonumber(del) or 0,
        binary = add == "-",
      }
    end
  end
  return files
end

--- Split ONE whole-range diff into per-file hunk lines - fugitive's trick:
--- its status buffer runs a single `diff` per section and serves every
--- inline `=` expansion from that one result; here one call serves every
--- <Tab>. Keys match the file table: post-image path from `+++ b/`, old
--- path for deletions. Bodies start after `+++` (the first `@@`), so the
--- diff/index preamble is dropped exactly as before; binary and mode-only
--- blocks never reach `+++` with a path and produce no entry.
---@return table<string, string[]>
local function parse_range_diff(lines)
  local by_path, cur, old = {}, nil, nil
  for _, l in ipairs(lines) do
    if l:find "^diff %-%-git " then
      cur, old = nil, nil -- header zone; body lines always carry a prefix char
    elseif cur then
      cur[#cur + 1] = l
    else
      old = l:match "^%-%-%- a/(.+)$" or old
      local path = l:match "^%+%+%+ b/(.+)$" or (l:find "^%+%+%+ /dev/null" and old)
      if path then
        cur = {}
        by_path[path] = cur
      end
    end
  end
  return by_path
end

--- Files of a range with fugitive-grade status letters (M/A/D/R/C).
---@return table[] files  { status, path, old_path?, add, del, binary }
---@param base_sha? string resolved sha of `base` (cache key; cumulative only)
function M.files(root, base, sha, mode, base_sha)
  local key = key_of("files", root, base, sha, mode, base_sha)
  spawn(key, files_args(root, mode, base, sha), parse_files)
  return await(key) or {}
end

--- Hunks-only diff for ONE file of the range (spliced under its row in the
--- files view), served from the whole-range split above.
---@return string[] lines
---@param base_sha? string resolved sha of `base` (cache key; cumulative only)
function M.file_diff(root, base, sha, mode, path, base_sha)
  local key = key_of("diff", root, base, sha, mode, base_sha)
  spawn(key, diff_args(root, mode, base, sha), parse_range_diff)
  return (await(key) or {})[path] or {}
end

-- Fire-and-forget cache warmers, called by the view right after a render -
-- fugitive computes its section diffs AT status-render time for the same
-- reason: the first expansion should never wait on a subprocess.

function M.warm_diff(root, base, sha, mode, base_sha)
  spawn(key_of("diff", root, base, sha, mode, base_sha), diff_args(root, mode, base, sha), parse_range_diff)
end

function M.warm_files(root, base, sha, mode, base_sha)
  spawn(key_of("files", root, base, sha, mode, base_sha), files_args(root, mode, base, sha), parse_files)
end

-- ------------------------------------------------------------------ verbs ---
-- The write half: everything that CHANGES a PR. Same forge split as the
-- reads above, same async shape - nothing here ever blocks the UI, and the
-- caller decides what to prompt (see pr.verbs).

--- Run a forge write command. Forge CLIs put failures on stderr, but not
--- all of them (tea prints some refusals on stdout), so the error handed
--- back is whichever stream actually said something.
---@param cb fun(ok: boolean, err?: string)
local function forge_run(cmd, root, cb)
  vim.system(cmd, { cwd = root, text = true }, function(r)
    vim.schedule(function()
      local err = vim.trim(r.stderr or "")
      if err == "" then err = vim.trim(r.stdout or "") end
      cb(r.code == 0, err ~= "" and err or nil)
    end)
  end)
end

--- Draft <-> ready. gh has a first-class verb; tea rewrites the title (see
--- WIP_PREFIXES) - `pr.title` is always the bare title, so the prefix is
--- simply added or omitted.
---@param draft boolean target state
---@param cb fun(ok: boolean, err?: string)
function M.set_draft(root, pr, draft, cb)
  if M.forge(root) == "gh" then
    local cmd = { "gh", "pr", "ready", tostring(pr.number) }
    if draft then cmd[#cmd + 1] = "--undo" end
    return forge_run(cmd, root, cb)
  end
  local title = (draft and WIP or "") .. (pr.title or "")
  forge_run({ "tea", "pr", "edit", tostring(pr.number), "--title", title }, root, cb)
end

--- `tea api` for the endpoints tea grew no verb for. Three traps, all of
--- them handled here: it exits 0 whatever the HTTP status, `-i` writes the
--- status line to STDERR while the body stays on stdout, and Gitea answers
--- some refusals (405 "already merged" among them) with an EMPTY `message`.
--- So the verdict is the status line, and that line is also the last-resort
--- error text - `message or ...` alone would surrender to the empty string.
---@param args string[] endpoint, then tea api flags
---@param cb fun(ok: boolean, err?: string)
local function tea_api(root, args, cb)
  local cmd = vim.list_extend({ "tea", "api", "-i", "-X", "POST" }, args)
  vim.system(cmd, { cwd = root, text = true }, function(r)
    vim.schedule(function()
      local line = (r.stderr or ""):match "HTTP/[%d%.]+ [^\r\n]*" or "no HTTP response"
      local status = tonumber(line:match "(%d%d%d)")
      if r.code == 0 and status and status < 300 then return cb(true) end
      local ok, body = pcall(vim.json.decode, r.stdout or "")
      local msg = ok and type(body) == "table" and vim.trim(body.message or "") or ""
      cb(false, msg ~= "" and msg or line)
    end)
  end)
end

local GH_STYLE = { squash = "--squash", merge = "--merge", rebase = "--rebase" }

--- opts.auto is THE escalation for a refused merge: rather than overriding
--- the checks the forge is waiting on, hand it the merge to perform once
--- they pass. Both forges then merge straight away if the PR turns out to be
--- mergeable already, so "auto" is never a worse outcome than plain merge.
--- gh spells it --auto; Gitea/Forgejo only expose it on the merge endpoint
--- (merge_when_checks_succeed), never through tea's own `pr merge`.
---@param opts {style?: string, auto?: boolean}  style: squash|merge|rebase
---@param cb fun(ok: boolean, err?: string)
function M.merge(root, pr, opts, cb)
  if M.forge(root) == "gh" then
    local cmd = { "gh", "pr", "merge", tostring(pr.number) }
    if opts.style then cmd[#cmd + 1] = GH_STYLE[opts.style] end
    if opts.auto then cmd[#cmd + 1] = "--auto" end
    return forge_run(cmd, root, cb)
  end
  if not opts.auto then
    local cmd = { "tea", "pr", "merge", tostring(pr.number) }
    if opts.style then vim.list_extend(cmd, { "--style", opts.style }) end
    return forge_run(cmd, root, cb)
  end
  -- {owner}/{repo} are tea's own placeholders, filled from the checkout.
  local args = { ("/repos/{owner}/{repo}/pulls/%d/merge"):format(pr.number), "-F", "merge_when_checks_succeed=true" }
  if opts.style then vim.list_extend(args, { "-f", "do=" .. opts.style }) end
  tea_api(root, args, cb)
end

--- The repo's own merge rules, so the merge prompt asks only what the repo
--- actually permits. gh answers exactly (viewerDefaultMergeMethod is the
--- method its web UI pre-selects for you); tea/Gitea exposes neither
--- allowed styles nor the default, so it reports "unknown" and the caller
--- falls through to the forge default.
---@param cb fun(policy: {default?: string, allowed: string[]})
function M.merge_policy(root, cb)
  if M.forge(root) ~= "gh" then return cb { allowed = {} } end
  local cmd = {
    "gh",
    "repo",
    "view",
    "--json",
    "viewerDefaultMergeMethod,mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed",
  }
  forge_json(cmd, root, "gh", function(d)
    if not d then return cb { allowed = {} } end
    local allowed = {}
    if d.squashMergeAllowed then allowed[#allowed + 1] = "squash" end
    if d.mergeCommitAllowed then allowed[#allowed + 1] = "merge" end
    if d.rebaseMergeAllowed then allowed[#allowed + 1] = "rebase" end
    cb { default = (d.viewerDefaultMergeMethod or ""):lower(), allowed = allowed }
  end)
end

---@param cb fun(ok: boolean, err?: string)
function M.close(root, pr, cb)
  local cmd = M.forge(root) == "gh" and { "gh", "pr", "close", tostring(pr.number) }
    or { "tea", "pr", "close", tostring(pr.number) }
  forge_run(cmd, root, cb)
end

--- Check the PR out onto a real local branch, in plain git.
---
--- NOT `gh/tea pr checkout`. tea's is broken on Forgejo: it detaches HEAD
--- onto the remote-TRACKING ref, leaves the index still holding the old tree
--- (so `git status` reports the entire repo as staged), and then exits
--- non-zero with "invalid checksum" - a half-applied checkout, which is worse
--- than a failed one. And neither CLI is needed here: the refspec has already
--- put the PR head in origin/pr/N locally, and the forge list already told us
--- the head branch name, so this is a pure-git, network-free operation.
---
--- Never clobbers work. An existing local branch of that name is only moved
--- when origin/pr/N already contains it (a fast-forward); a branch carrying
--- commits the PR does not have is reported, not overwritten.
---@param cb fun(ok: boolean, err?: string)
function M.checkout(root, pr, cb)
  local ref = M.ref(pr.number)
  local branch = pr.headRefName
  if not branch or branch == "" then return cb(false, "PR #" .. pr.number .. " has no head branch name") end

  local exists = git { "-C", root, "rev-parse", "--verify", "--quiet", "refs/heads/" .. branch } ~= nil
  if exists and git { "-C", root, "merge-base", "--is-ancestor", branch, ref } == nil then
    return cb(false, ("local branch %s has commits that are not in #%d"):format(branch, pr.number))
  end

  -- -B is the fast-forward (or create) in one call; the ancestor check above
  -- is what makes the reset it performs safe.
  forge_run({ "git", "checkout", "-B", branch, ref }, root, function(ok, err)
    if not ok then return cb(false, err) end
    -- Upstream so a fixup pushes back to the PR. Same-repo PRs have an
    -- origin/<branch>; a fork PR has none, and then there is simply no
    -- upstream to set - not an error, so the checkout still counts.
    if git { "-C", root, "rev-parse", "--verify", "--quiet", "refs/remotes/origin/" .. branch } then
      git { "-C", root, "branch", "--set-upstream-to=origin/" .. branch, branch }
    end
    cb(true)
  end)
end

-- ----------------------------------------------------------- working tree ---
-- The reads and writes that concern a TREE rather than a PR. Only pr.tree
-- calls these; every other consumer in this plugin is ref-only and works
-- whatever any tree happens to be at. `root` here is any working tree - the
-- main checkout or one of the PR worktrees, since git -C makes no distinction.

--- Tracked changes only. Untracked files do not block a checkout in general,
--- so counting them would refuse checkouts git itself would perform.
function M.dirty(root)
  local out = git { "-C", root, "status", "--porcelain", "--untracked-files=no" } or {}
  return #out > 0
end

--- Where a tree is. `branch` is nil on a detached HEAD, which is exactly what
--- --quiet reports by exiting non-zero.
---@return {sha: string, branch: string?}
function M.head(root)
  local sha = git { "-C", root, "rev-parse", "--short", "HEAD" }
  local branch = git { "-C", root, "symbolic-ref", "--short", "--quiet", "HEAD" }
  return { sha = sha and sha[1] or "", branch = branch and branch[1] or nil }
end

--- Detached checkout of one commit, inside `root`. Used to MOVE an existing PR
--- worktree to another commit of the same PR rather than rebuild it.
---@param cb fun(ok: boolean, err?: string)
function M.detach(root, sha, cb) forge_run({ "git", "checkout", "--detach", sha }, root, cb) end

-- ------------------------------------------------------------- worktrees ---
-- How a PR becomes real files without touching your checkout. Detached on
-- purpose: a worktree holding a BRANCH locks that branch out of every other
-- worktree, which would make materialising a PR quietly steal it.

--- Create a worktree detached at `sha`. Parent directories are made first:
--- `worktree add` creates the leaf but not `.worktrees/` itself.
---@param cb fun(ok: boolean, err?: string)
function M.worktree_add(root, path, sha, cb)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  forge_run({ "git", "-C", root, "worktree", "add", "--detach", path, sha }, root, cb)
end

--- Remove a worktree, synchronously. --force because these are detached and
--- disposable; the caller has already refused to remove a dirty one.
---@return boolean ok
function M.worktree_remove(root, path) return git { "-C", root, "worktree", "remove", "--force", path } ~= nil end

--- Drop administrative entries for worktrees whose directory is gone.
function M.worktree_prune(root) git { "-C", root, "worktree", "prune" } end

--- Every worktree path registered on this repo, main checkout included.
---@return string[]
function M.worktree_list(root)
  local out = git { "-C", root, "worktree", "list", "--porcelain" } or {}
  local paths = {}
  for _, line in ipairs(out) do
    local p = line:match "^worktree (.+)$"
    if p then paths[#paths + 1] = p end
  end
  return paths
end

--- origin as a browsable https base. Both scp-style (git@host:owner/repo) and
--- ssh:// remotes normalize; anything that does not end up http(s) is not a
--- URL we can open and comes back nil.
---@return string? base
local function web_base(root)
  local out = git { "-C", root, "remote", "get-url", "origin" }
  local url = out and out[1]
  if not url then return nil end
  url = url:gsub("%.git$", ""):gsub("^ssh://git@", "https://"):gsub("^git@([^:]+):", "https://%1/")
  return url:find "^https?://" and url or nil
end

--- Browser URL for a PR, derived from origin - no subprocess round trip to
--- `gh pr view --web` just to learn a URL we already know.
---@return string? url
function M.web_url(root, number)
  local base = web_base(root)
  if not base then return nil end
  -- github.com/o/r/pull/N vs gitea/forgejo o/r/pulls/N.
  return base .. (M.forge(root) == "gh" and "/pull/" or "/pulls/") .. number
end

--- Browser URL for a commit. Unlike PRs, both forges spell this the same way.
---@return string? url
function M.commit_url(root, sha)
  local base = web_base(root)
  return base and (base .. "/commit/" .. sha) or nil
end

return M
