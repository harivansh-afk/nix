-- pr.ci.api: every CI query in this plugin, on both forges.
--
-- pr.data owns git and the PR metadata; this owns checks, jobs and job logs.
-- Everything here is async and normalises to ONE job shape, so nothing above
-- this file knows which forge answered:
--
--   { id?, name, workflow?, run_id?, url?, status, conclusion?,
--     started_at?, finished_at? }   -- *_at are TRUE epoch seconds (pr.fmt)
--
-- Two depths exist per commit, and only Forgejo distinguishes them:
--   M.runs    the run list for one sha, ONE request  - feeds an orb
--   M.checks  full per-job detail                    - feeds the pane
-- GitHub answers both in a single GraphQL round trip, so there M.runs IS
-- M.checks. Forgejo's detail costs 1 + #runs requests, which a one-character
-- orb must not pay fifty times over.
--
-- The Actions RUNS API is the only CI source this plugin trusts. The
-- combined-status endpoint (/commits/{sha}/status) - which also backs the
-- `ci` field of `tea pr list` - was measured lying in both directions on
-- Forgejo 16: a commit whose update-flake-lock run FAILED reported
-- state=success, because the crashed run never posted a commit status at
-- all; and cancelled runs reported state=failure. Runs truth and status
-- truth cannot be mixed, or two surfaces disagree about the same commit.

local fmt = require "pr.fmt"

local M = {}

--- Async plumbing from the one process engine. Captured as bare locals
--- because `run` is what this file calls a workflow run everywhere below.
local sh = require("pr.run").sh
local json = require("pr.run").json

--- ISO -> true epoch. Kept as a named export because every caller of this
--- module already speaks api.epoch; the arithmetic lives in pr.fmt.
M.epoch = fmt.epoch

--- True unix now - the frame every *_at above is in.
function M.now() return os.time() end

--- `{owner}`/`{repo}` are placeholders BOTH CLIs expand from the checkout, so
--- no path here has to know the slug. On gh they expand to the BASE repo,
--- which is where a fork PR's checks live.
--- `-i` on every tea call, because tea exits 0 whatever the HTTP status: it
--- moves the status line onto stderr (the body stays clean on stdout) and
--- that is the only thing pr.run can judge a tea response by. Without it a
--- 404 arrives looking exactly like a successful answer - an unstarted job's
--- "job not started" error would be painted into the log buffer as if the
--- forge had said it was the log.
local function gh_api(path) return { "gh", "api", path } end
local function tea_api(path) return { "tea", "api", "-i", path } end

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

--- The run list for one head sha - the single-request read the orbs pay for.
--- Forgejo filters ?head_sha= by EXACT string, so callers must hand over the
--- full 40 chars (pr.data rows carry `full` for precisely this).
---@param cb fun(runs?: table[], err?: string)  { status, conclusion } each
local function tea_runs(root, sha, cb)
  json(tea_api("/repos/{owner}/{repo}/actions/runs?head_sha=" .. sha), root, function(data, err)
    if err then return cb(nil, err) end
    cb((data or {}).workflow_runs or {})
  end)
end

local function tea_checks(root, sha, cb)
  tea_runs(root, sha, function(runs, err)
    if err then return cb(nil, err) end
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

--- The cheapest TRUTHFUL read of one commit's CI: full job detail where one
--- request already buys it (GitHub's GraphQL), run-level summaries where
--- detail would cost 1 + #runs requests (Forgejo). `detail` reports which
--- arrived, so the store knows whether a pane can be served from this or
--- must escalate to M.checks.
---
--- Items are always job-shaped ({ name, status, conclusion, url, *_at }); a
--- Forgejo run stands in as one item wearing its workflow's name.
---@param forge "gh"|"tea"
---@param cb fun(items?: table[], detail?: boolean, err?: string)
function M.summary(root, forge, sha, cb)
  if forge == "gh" then
    return gh_checks(root, sha, function(jobs, err) cb(jobs, true, err) end)
  end
  tea_runs(root, sha, function(runs, err)
    if not runs then return cb(nil, nil, err) end
    local items = {}
    for _, r in ipairs(runs) do
      items[#items + 1] = {
        name = tostring(r.workflow_id or "?"):gsub("%.ya?ml$", ""),
        status = r.status,
        conclusion = r.conclusion,
        url = r.html_url,
        started_at = M.epoch(r.started),
        finished_at = M.epoch(r.stopped),
      }
    end
    cb(items, false)
  end)
end

return M
