-- pr.ci.api: every CI query in this plugin, on both forges.
--
-- pr.data owns git and the PR metadata; this owns checks, jobs and job logs.
-- Everything here is async and normalises to ONE job shape, so nothing above
-- this file knows which forge answered:
--
--   { id?, name, workflow?, run_id?, url?, status, conclusion?,
--     started_at?, finished_at? }   -- *_at are epoch seconds
--
-- GitHub answers a whole commit's checks in a single GraphQL round trip, job
-- ids included. Forgejo/Gitea has no such rollup, so it takes the two-step
-- REST path: the runs for a head sha, then each run's jobs. Both endpoints
-- were verified against Forgejo 16.
--
-- Two query paths exist on purpose. M.rollup_all answers N PRs in ONE call
-- and is what the pr://list orbs read; M.checks answers ONE sha in full
-- detail and is what the pane reads. Feeding the list through M.checks would
-- be N round trips - the very cost pr.data.prs was split up to avoid.

local M = {}

-- --------------------------------------------------------------- plumbing ---

--- ISO-8601 UTC -> epoch seconds, in the same skewed frame as M.now. Lua has
--- no portable "UTC fields -> epoch", so both sides go through os.time (which
--- reads its table as LOCAL time) with isdst pinned: the offsets then cancel
--- exactly and a subtraction of the two is a true elapsed time. See pr.fmt.ago.
---@return integer? epoch
function M.epoch(iso)
  local y, mo, d, h, mi, s = tostring(iso or ""):match "(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)"
  if not y then return nil end
  return os.time { year = y, month = mo, day = d, hour = h, min = mi, sec = s, isdst = false }
end

--- "Now", in M.epoch's frame.
function M.now() return os.time(os.date "!*t") end

---@param cb fun(out?: string, err?: string)
local function sh(cmd, root, cb)
  vim.system(cmd, { cwd = root, text = true }, function(r)
    vim.schedule(function()
      if r.code ~= 0 then
        local e = vim.trim(r.stderr or "")
        if e == "" then e = vim.trim(r.stdout or "") end
        -- Both CLIs answer API failures with a JSON body carrying `message`.
        local ok, body = pcall(vim.json.decode, e)
        if ok and type(body) == "table" and body.message then e = body.message end
        return cb(nil, e ~= "" and e or ("exited with code " .. r.code))
      end
      cb(r.stdout or "")
    end)
  end)
end

---@param cb fun(data?: table, err?: string)
local function json(cmd, root, cb)
  sh(cmd, root, function(out, err)
    if err then return cb(nil, err) end
    local ok, decoded = pcall(vim.json.decode, out, { luanil = { object = true, array = true } })
    if not ok or type(decoded) ~= "table" then return cb(nil, "malformed JSON from the forge") end
    cb(decoded)
  end)
end

--- `{owner}`/`{repo}` are placeholders BOTH CLIs expand from the checkout, so
--- no path here has to know the slug. On gh they expand to the BASE repo,
--- which is where a fork PR's checks live.
local function gh_api(path) return { "gh", "api", path } end
local function tea_api(path) return { "tea", "api", path } end

-- ----------------------------------------------------------------- github ---

--- A commit's checks in one request. `databaseId` on a CheckRun is the
--- Actions job id, which is what the log endpoint takes; detailsUrl carries
--- the run id. Non-Actions StatusContexts come back too, with no job id -
--- they are real checks that simply have no log to open.
local CHECKS_FOR_REV = [[
query($owner:String!,$repo:String!,$expr:String!){
  repository(owner:$owner,name:$repo){
    object(expression:$expr){
      ... on Commit{
        oid
        statusCheckRollup{
          contexts(first:100){
            nodes{
              __typename
              ... on CheckRun{
                name status conclusion detailsUrl databaseId startedAt completedAt
                checkSuite{ workflowRun{ databaseId workflow{ name } } }
              }
              ... on StatusContext{ context state targetUrl createdAt }
            }
          }
        }
      }
    }
  }
}]]

--- Flattens the rollup, keeping the newest of each (workflow, name): a rerun
--- leaves the superseded attempt sitting in the rollup alongside its retry.
local function gh_jobs(nodes)
  local out, seen = {}, {}
  for _, n in ipairs(nodes or {}) do
    local j
    if n.__typename == "CheckRun" then
      local run_id, job_id = (n.detailsUrl or ""):match "/actions/runs/(%d+)/job/(%d+)"
      j = {
        id = tonumber(job_id) or n.databaseId,
        name = n.name,
        workflow = vim.tbl_get(n, "checkSuite", "workflowRun", "workflow", "name"),
        run_id = tonumber(run_id),
        url = n.detailsUrl,
        status = n.status,
        conclusion = n.conclusion,
        started_at = M.epoch(n.startedAt),
        finished_at = M.epoch(n.completedAt),
      }
    elseif n.__typename == "StatusContext" then
      j = { name = n.context, conclusion = n.state, url = n.targetUrl, started_at = M.epoch(n.createdAt) }
    end
    if j then
      local key = (j.workflow or "") .. "\0" .. (j.name or "")
      local prev = seen[key]
      if not prev then
        out[#out + 1] = j
        seen[key] = #out
      elseif (j.started_at or 0) >= (out[prev].started_at or 0) then
        out[prev] = j
      end
    end
  end
  return out
end

local function gh_checks(root, sha, cb)
  local cmd = {
    "gh",
    "api",
    "graphql",
    "-F",
    "owner={owner}",
    "-F",
    "repo={repo}",
    "-f",
    "expr=" .. sha,
    "-f",
    "query=" .. CHECKS_FOR_REV,
  }
  json(cmd, root, function(data, err)
    if err then return cb(nil, err) end
    if data.errors and data.errors[1] then return cb(nil, data.errors[1].message or "GraphQL error") end
    local obj = vim.tbl_get(data, "data", "repository", "object")
    if not obj then return cb(nil, "no such commit on the remote: " .. sha) end
    local nodes = vim.tbl_get(obj, "statusCheckRollup", "contexts", "nodes")
    cb(gh_jobs(nodes))
  end)
end

-- --------------------------------------------------------------- forgejo ---
-- Two steps, because Gitea/Forgejo has no rollup: the runs for this head sha
-- (?head_sha is a real server-side filter - verified), then each run's jobs.
-- The jobs endpoint carries no timing at all, so a job inherits its run's
-- start; that is what the elapsed column ticks from. Exact per-job durations
-- would need /commits/{sha}/statuses as a third call, which is not worth it
-- while the run header already shows the total.

local function tea_jobs_of_run(root, run, cb)
  json(tea_api(("/repos/{owner}/{repo}/actions/runs/%d/jobs"):format(run.id)), root, function(jobs, err)
    if err then return cb(nil, err) end
    local out = {}
    for i, j in ipairs(jobs or {}) do
      out[#out + 1] = {
        id = j.id,
        name = j.name,
        workflow = (run.workflow_id or ""):gsub("%.ya?ml$", ""),
        run_id = run.id,
        -- Forgejo's per-job page is the run page plus the job's INDEX in the
        -- run, not its id (matches the target_url on its commit statuses).
        url = run.html_url and ("%s/jobs/%d"):format(run.html_url, i - 1) or nil,
        status = j.status,
        started_at = M.epoch(run.started),
        finished_at = M.epoch(run.stopped),
        -- These times are the RUN's, not this job's. Good enough to tick a
        -- running job's elapsed from, useless as a finished job's duration:
        -- three jobs of a 45s run would each claim they took 45s.
        inherited = true,
      }
    end
    cb(out)
  end)
end

local function tea_checks(root, sha, cb)
  json(tea_api("/repos/{owner}/{repo}/actions/runs?head_sha=" .. sha), root, function(data, err)
    if err then return cb(nil, err) end
    local runs = (data or {}).workflow_runs or {}
    if #runs == 0 then return cb {} end
    -- Fan out over the runs and answer once the last one lands. A PR has one
    -- or two workflows in practice, so this is not a fan-out worth batching.
    local out, left, failed = {}, #runs, nil
    for _, run in ipairs(runs) do
      tea_jobs_of_run(root, run, function(jobs, e)
        failed = failed or e
        vim.list_extend(out, jobs or {})
        left = left - 1
        if left == 0 then
          if #out == 0 and failed then return cb(nil, failed) end
          cb(out)
        end
      end)
    end
  end)
end

-- ------------------------------------------------------------------ public ---

--- Every check on one commit.
---@param forge "gh"|"tea"
---@param cb fun(jobs?: table[], err?: string)
function M.checks(root, forge, sha, cb)
  if forge == "gh" then return gh_checks(root, sha, cb) end
  tea_checks(root, sha, cb)
end

--- A job's raw log. GitHub refuses this while the job is still running
--- (documented API limitation, cli/cli#3484); Forgejo serves what the runner
--- has written so far, so a running job there tails.
---@param cb fun(text?: string, err?: string)
function M.job_log(root, forge, id, cb)
  local path = ("/repos/{owner}/{repo}/actions/jobs/%d/logs"):format(id)
  local cmd = forge == "gh" and gh_api(path:sub(2)) or tea_api(path)
  sh(cmd, root, function(out, err)
    if err then return cb(nil, err) end
    cb((out:gsub("^\239\187\191", ""))) -- strip the BOM GitHub prefixes
  end)
end

--- A job's steps. GitHub only - Forgejo exposes no step breakdown, and the
--- `##[group]` markers in its log are the closest thing it has.
---@param cb fun(steps?: table[], err?: string)
function M.job_steps(root, forge, id, cb)
  if forge ~= "gh" then return cb(nil, "no step API on this forge") end
  json(gh_api(("repos/{owner}/{repo}/actions/jobs/%d"):format(id)), root, function(data, err)
    if err then return cb(nil, err) end
    cb((data or {}).steps or {})
  end)
end

--- One rollup state per open PR: the cheap call the pr://list orbs read.
--- gh's statusCheckRollup mixes CheckRun {status, conclusion} with
--- StatusContext {state}: any failure wins, any in-flight check means
--- pending, otherwise success. nil = no CI at all on that PR.
---@return "success"|"failure"|"pending"|nil
local function rollup_state(checks)
  if type(checks) ~= "table" or #checks == 0 then return nil end
  local state = "success"
  for _, ch in ipairs(checks) do
    local s = tostring(ch.conclusion or ch.state or ""):upper()
    if ch.status and ch.status ~= "COMPLETED" then s = "PENDING" end
    if s == "FAILURE" or s == "ERROR" or s == "TIMED_OUT" or s == "ACTION_REQUIRED" then return "failure" end
    if s == "PENDING" or s == "EXPECTED" or s == "" then state = "pending" end
    -- SKIPPED / NEUTRAL / CANCELLED / SUCCESS don't demote the rollup.
  end
  return state
end

--- tea's `ci` field is the Gitea commit-status state as a bare string
--- ("success", "failure", "error", "pending", "warning", "" for none).
local function tea_state(s)
  s = tostring(s or ""):lower()
  if s == "success" then return "success" end
  if s == "failure" or s == "error" then return "failure" end
  if s == "pending" or s == "warning" then return "pending" end
  return nil
end

--- PR number -> rollup state, for every open PR, in one call.
---@param cb fun(map?: table<integer, string>, err?: string)
function M.rollup_all(root, forge, cb)
  local cmd = forge == "gh" and { "gh", "pr", "list", "--limit", "100", "--json", "number,statusCheckRollup" }
    or { "tea", "pr", "list", "--output", "json", "--limit", "100", "--fields", "index,ci" }
  json(cmd, root, function(rows, err)
    if not rows then return cb(nil, err) end
    local map = {}
    for _, p in ipairs(rows) do
      if forge == "gh" then
        map[p.number] = rollup_state(p.statusCheckRollup)
      else
        map[tonumber(p.index) or -1] = tea_state(p.ci)
      end
    end
    cb(map)
  end)
end

return M
