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

-- ------------------------------------------------------------------ cache ---
-- The diff between two commits is immutable, so every entry is keyed on
-- RESOLVED shas (never ref names): when origin/<base> or origin/pr/N moves,
-- new shas mean new keys and stale entries are simply never hit again -
-- invalidation is structural, not bookkeeping. M.fetch clears outright (the
-- one place this plugin moves refs) and the size cap clears wholesale;
-- both are memory valves, not correctness requirements.

local cache, cache_n = {}, 0
local CACHE_MAX = 512

local function put(key, val)
  if cache_n >= CACHE_MAX then
    cache, cache_n = {}, 0
  end
  cache[key], cache_n = val, cache_n + 1
  return val
end

--- Global flags on EVERY git call, stolen from fugitive's status runner:
--- never take the optional index lock for a read, and never octal-quote
--- non-ASCII paths (paths here must match buffer rows byte-for-byte).
local GIT = { "git", "--no-optional-locks", "-c", "core.quotePath=false" }

---@param args string[]
---@return string[]? lines, string? err
local function git(args)
  local out = vim.fn.systemlist(vim.list_extend(vim.deepcopy(GIT), args))
  if vim.v.shell_error ~= 0 then return nil, table.concat(out or {}, "\n") end
  return out
end

-- ------------------------------------------------------------------- jobs ---
-- Fugitive's core perf move (fugitive#Execute + fugitive#Wait): START a git
-- call the moment it is known to be needed, BLOCK only when the answer is
-- consumed. spawn() begins filling a cache slot in the background; await()
-- is the sync read, riding an in-flight job instead of forking a second
-- process. The view warms the slots the next keystroke will need.

local jobs = {} ---@type table<string, {obj: vim.SystemObj, settle: fun(r: vim.SystemCompleted)}>

---@param key string cache slot the job fills
---@param args string[] git args
---@param parse fun(lines: string[]): any pure Lua - on_exit is a fast context
local function spawn(key, args, parse)
  if cache[key] ~= nil or jobs[key] then return end
  local job = {}
  job.settle = function(r)
    if jobs[key] ~= job then return end -- clear_cache dropped this job
    jobs[key] = nil
    if r.code == 0 then put(key, parse(vim.split(r.stdout or "", "\n", { trimempty = true }))) end
  end
  jobs[key] = job
  job.obj = vim.system(vim.list_extend(vim.deepcopy(GIT), args), { text = true }, job.settle)
end

--- Cache read that first waits for (and settles) the in-flight job, if any.
--- settle is idempotent, so racing git's own on_exit is harmless.
local function await(key)
  local job = jobs[key]
  if job then job.settle(job.obj:wait()) end
  return cache[key]
end

function M.clear_cache()
  cache, cache_n, jobs = {}, 0, {}
end

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

--- PR list, forge-agnostic. Metadata only - async, never blocks the UI.
--- Deliberately NO CI here: the status rollup is the slow half of the list
--- call (measured: gh on neovim/neovim 0.8s bare -> 11s + HTTP 504 with
--- statusCheckRollup). Every CI query lives in pr.ci.api instead, and
--- pr.list paints the orbs from pr.ci.rollup_all behind this render.
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

--- Commits of a PR, OLDEST FIRST so index 1 is the first commit authored
--- (matches GitHub's Commits tab, and makes `]c` walk toward the tip).
---@return table[] commits  { sha, author, ago, subject }
function M.commits(root, base, target)
  local out = git {
    "-C",
    root,
    "log",
    "--reverse",
    "--format=%h\t%an\t%ar\t%s",
    base .. ".." .. target,
  } or {}
  local commits = {}
  for _, line in ipairs(out) do
    local sha, an, ar, subject = line:match "^(%S+)\t(.-)\t(.-)\t(.*)$"
    if sha then commits[#commits + 1] = { sha = sha, author = an, ago = ar, subject = subject } end
  end
  return commits
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

--- Browser URL for a PR, derived from origin - no subprocess round trip to
--- `gh pr view --web` just to learn a URL we already know. Both scp-style
--- (git@host:owner/repo) and ssh:// remotes normalize to https.
---@return string? url
function M.web_url(root, number)
  local out = git { "-C", root, "remote", "get-url", "origin" }
  local url = out and out[1]
  if not url then return nil end
  url = url:gsub("%.git$", ""):gsub("^ssh://git@", "https://"):gsub("^git@([^:]+):", "https://%1/")
  if not url:find "^https?://" then return nil end
  -- github.com/o/r/pull/N vs gitea/forgejo o/r/pulls/N.
  return url .. (M.forge(root) == "gh" and "/pull/" or "/pulls/") .. number
end

return M
