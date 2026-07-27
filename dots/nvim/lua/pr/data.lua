-- pr.data: every git/gh query behind the PR review flow.
-- Diff content always comes from LOCAL refs (see refspec below), never the network.
-- `gh` is used only for PR metadata (titles, authors, base branch).

local M = {}

local REFSPEC = "+refs/pull/*/head:refs/remotes/origin/pr/*"

-- ------------------------------------------------------------------ cache ---
-- The diff between two commits is immutable, so every entry is keyed on
-- RESOLVED shas (never ref names): when origin/<base> or origin/pr/N moves,
-- new shas mean new keys and stale entries are simply never hit again -
-- invalidation is structural, not bookkeeping. M.fetch clears outright (the
-- one place this plugin moves refs) and the size cap clears wholesale;
-- both are memory valves, not correctness requirements.

local cache, cache_n = {}, 0
local CACHE_MAX = 512

local function cached(key, fn)
  local hit = cache[key]
  if hit ~= nil then return hit end
  local val = fn()
  if cache_n >= CACHE_MAX then
    cache, cache_n = {}, 0
  end
  cache[key], cache_n = val, cache_n + 1
  return val
end

function M.clear_cache()
  cache, cache_n = {}, 0
end

---@param args string[]
---@return string[]? lines, string? err
local function git(args)
  local out = vim.fn.systemlist(vim.list_extend({ "git" }, args))
  if vim.v.shell_error ~= 0 then return nil, table.concat(out or {}, "\n") end
  return out
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
function M.resolve(root, ref)
  local out = git { "-C", root, "rev-parse", "--short", ref }
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

--- PR list, forge-agnostic. Metadata only - async, never blocks the UI.
--- Results are normalized to the gh shape:
---   { number, title, author = { login }, baseRefName, isDraft, updatedAt }
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
      "index,title,author,base,updated",
    }
  end

  vim.system(cmd, { cwd = root, text = true }, function(r)
    vim.schedule(function()
      if r.code ~= 0 then return cb(nil, vim.trim(r.stderr or (forge .. " failed"))) end
      local ok, decoded = pcall(vim.json.decode, r.stdout)
      if not ok or type(decoded) ~= "table" then return cb(nil, "could not parse " .. forge .. " output") end
      if forge == "gh" then return cb(decoded) end

      -- Normalize tea: index is a string, drafts are the WIP: title
      -- convention, `base` is the target branch.
      local prs = {}
      for _, p in ipairs(decoded) do
        prs[#prs + 1] = {
          number = tonumber(p.index),
          title = p.title,
          author = { login = p.author or "?" },
          baseRefName = p.base and p.base ~= "" and p.base or "main",
          isDraft = (p.title or ""):match "^WIP" ~= nil,
          updatedAt = p.updated,
        }
      end
      cb(prs)
    end)
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

--- Files of a range with fugitive-grade status letters (M/A/D/R/C).
--- `--numstat` and `--name-status` emit files in identical order for the
--- same diff, so the two outputs zip together by index.
---@return table[] files  { status, path, old_path?, add, del, binary }
---@param base_sha? string resolved sha of `base` (cache key; cumulative only)
function M.files(root, base, sha, mode, base_sha)
  local key = table.concat({ "files", root, mode, mode == "incremental" and sha or (base_sha or base), sha }, "\0")
  return cached(key, function() return M.files_uncached(root, base, sha, mode) end)
end

function M.files_uncached(root, base, sha, mode)
  local range = mode == "incremental" and { sha .. "^", sha } or { base .. "..." .. sha }

  local num = git(vim.list_extend({ "-C", root, "diff", "--numstat", "-M" }, vim.deepcopy(range))) or {}
  local st = git(vim.list_extend({ "-C", root, "diff", "--name-status", "-M" }, range)) or {}

  local files = {}
  for i, line in ipairs(st) do
    local letter, rest = line:match "^(%a)%d*\t(.+)$"
    if not letter then
      letter, rest = line:match "^(%?)%?\t(.+)$" -- untracked never appears here, but be safe
    end
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

--- Hunks-only diff for ONE file of the range (spliced under its row in the
--- files view). The diff/index/---/+++ preamble is stripped: the file row
--- above already names the file, and diffs.nvim's parser takes the filename
--- from that row, so the noise carries zero information here.
---@return string[] lines
---@param base_sha? string resolved sha of `base` (cache key; cumulative only)
function M.file_diff(root, base, sha, mode, path, base_sha)
  local key = table.concat({ "diff", root, mode, mode == "incremental" and sha or (base_sha or base), sha, path }, "\0")
  return cached(key, function() return M.file_diff_uncached(root, base, sha, mode, path) end)
end

function M.file_diff_uncached(root, base, sha, mode, path)
  local args = { "-C", root, "diff", "--no-color", "--no-ext-diff" }
  if mode == "incremental" then
    vim.list_extend(args, { sha .. "^", sha })
  else
    vim.list_extend(args, { base .. "..." .. sha })
  end
  vim.list_extend(args, { "--", path })
  local raw = git(args) or {}
  for i, line in ipairs(raw) do
    if line:match "^@@" then return vim.list_slice(raw, i) end
  end
  return {} -- binary or metadata-only change: nothing textual to splice
end

--- Totals for the winbar, without re-shelling for each file.
function M.totals(files)
  local a, d = 0, 0
  for _, f in ipairs(files) do
    a, d = a + f.add, d + f.del
  end
  return #files, a, d
end

return M
