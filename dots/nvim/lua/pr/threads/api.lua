-- pr.threads.api: every conversation query in this plugin, on both forges.
--
-- pr.ci.api owns checks; this owns what people SAID - review verdicts, code
-- threads and conversation comments. Everything here is async and normalises
-- to ONE item vocabulary, so nothing above this file knows which forge
-- answered:
--
--   { kind="comment", id, author, body, ts?, url? }             -- conversation
--   { kind="review",  id, verdict, author, body, ts?, url?,
--     dismissed? }                                              -- a verdict
--   { kind="thread",  key, path, line?, resolved?, outdated?,
--     ts?, url?, comments={ {author, body, ts?} } }             -- code-anchored
--
-- verdict is "approved" | "changes" | "commented"; ts are TRUE epoch seconds
-- (pr.fmt.epoch). `line` is the NEW-side line the thread anchors on, which is
-- what pr.tree.open jumps to.
--
-- Costs, measured against the live forges (2026-08):
--   GitHub   ONE GraphQL round trip - reviewThreads carries isResolved,
--            isOutdated and line directly, which its REST API never groups.
--   Forgejo  2 + #reviews-with-inline-comments requests: issue comments,
--            the review list, then one call per review that holds comments.
--            The three sources are DISJOINT (verified: review bodies do not
--            leak into /issues/{n}/comments), so nothing is deduped here.

local fmt = require "pr.fmt"
local run = require "pr.run"

local M = {}

local json = run.json

local function tea_api(path) return { "tea", "api", "-i", path } end

-- ---------------------------------------------------------------- verdicts ---

--- Both forges' review states, collapsed to three words. PENDING is an
--- UNSUBMITTED review (the forge shows it to its author only) and Forgejo's
--- REQUEST_REVIEW rows are bookkeeping, not speech - both are dropped.
local VERDICT = {
  APPROVED = "approved",
  CHANGES_REQUESTED = "changes",
  REQUEST_CHANGES = "changes",
  COMMENTED = "commented",
  COMMENT = "commented",
  DISMISSED = "commented", -- a dismissed verdict is history, not a verdict; renders dim
}

-- ------------------------------------------------------------------- hunks ---

--- The NEW-side line a review comment anchors on, from its diff_hunk: the
--- hunk's last line IS the commented line (both forges build the excerpt
--- that way), so walk the hunk counting non-deleted lines from the header's
--- +c start. A comment on a DELETED line has no new-side home; the nearest
--- surviving line above it stands in, which is where a reader wants to land
--- anyway.
---@param hunk string?
---@return integer? line
function M.hunk_line(hunk)
  if not hunk or hunk == "" then return nil end
  local lines = vim.split(hunk, "\n", { plain = true })
  local start = lines[1] and lines[1]:match "^@@ %-%d+[,%d]* %+(%d+)"
  if not start then return nil end
  local new, last = tonumber(start) - 1, nil
  for i = 2, #lines do
    if lines[i]:sub(1, 1) ~= "-" then
      new = new + 1
      last = new
    end
  end
  return last or tonumber(start)
end

-- ----------------------------------------------------------------- github ---

--- The whole conversation in one round trip, reviewThreads included - the
--- same single-request shape CHECKS_FOR_REV buys for CI.
local TALK_FOR_PR = [[
query($owner:String!,$repo:String!,$num:Int!){
  repository(owner:$owner,name:$repo){
    pullRequest(number:$num){
      comments(first:100){nodes{databaseId author{login} body createdAt url}}
      reviews(first:100){nodes{databaseId author{login} state body submittedAt url}}
      reviewThreads(first:100){nodes{
        isResolved isOutdated path line originalLine
        comments(first:100){nodes{author{login} body createdAt url}}
      }}
    }
  }
}]]

local function gh_talk(root, number, cb)
  local cmd = {
    "gh",
    "api",
    "graphql",
    "-F",
    "owner={owner}",
    "-F",
    "repo={repo}",
    "-F",
    "num=" .. number,
    "-f",
    "query=" .. TALK_FOR_PR,
  }
  json(cmd, root, function(data, err)
    if err then return cb(nil, err) end
    if data.errors and data.errors[1] then return cb(nil, data.errors[1].message or "GraphQL error") end
    local pr = vim.tbl_get(data, "data", "repository", "pullRequest")
    if not pr then return cb(nil, "no such PR on the remote: #" .. number) end

    local items = {}
    for _, c in ipairs(vim.tbl_get(pr, "comments", "nodes") or {}) do
      items[#items + 1] = {
        kind = "comment",
        id = c.databaseId,
        author = vim.tbl_get(c, "author", "login") or "?",
        body = c.body or "",
        ts = fmt.epoch(c.createdAt),
        url = c.url,
      }
    end
    for _, r in ipairs(vim.tbl_get(pr, "reviews", "nodes") or {}) do
      local verdict = VERDICT[r.state]
      -- An empty-bodied "commented" review is the shell GitHub wraps around
      -- inline comments; the thread rows already say everything it does.
      if verdict and not (verdict == "commented" and (r.body or "") == "") then
        items[#items + 1] = {
          kind = "review",
          id = r.databaseId,
          verdict = verdict,
          dismissed = r.state == "DISMISSED" or nil,
          author = vim.tbl_get(r, "author", "login") or "?",
          body = r.body or "",
          ts = fmt.epoch(r.submittedAt),
          url = r.url,
        }
      end
    end
    for _, t in ipairs(vim.tbl_get(pr, "reviewThreads", "nodes") or {}) do
      local comments = {}
      for _, c in ipairs(vim.tbl_get(t, "comments", "nodes") or {}) do
        comments[#comments + 1] = {
          author = vim.tbl_get(c, "author", "login") or "?",
          body = c.body or "",
          ts = fmt.epoch(c.createdAt),
        }
      end
      if #comments > 0 then
        local line = t.line or t.originalLine
        items[#items + 1] = {
          kind = "thread",
          key = (t.path or "?") .. ":" .. tostring(line or 0),
          path = t.path,
          line = line,
          resolved = t.isResolved or nil,
          outdated = t.isOutdated or nil,
          ts = comments[#comments].ts,
          url = vim.tbl_get(t, "comments", "nodes", 1, "url"),
          comments = comments,
        }
      end
    end
    cb(items)
  end)
end

-- ---------------------------------------------------------------- forgejo ---
-- Three reads, fanned out where they can be. Forgejo has no thread objects
-- at all: a reply is just another review's comment at the same path and
-- position, so threads are REBUILT here by grouping every review's inline
-- comments on (path, anchor line) and sorting each group by time. A thread
-- is resolved when its last comment carries a resolver (Forgejo resolves
-- whole conversations, and stamps the field on the comments).

local function tea_talk(root, number, cb)
  local items, threads = {}, {}
  local pending, failed = 2, nil

  local function settle()
    pending = pending - 1
    if pending > 0 then return end
    if failed and #items == 0 and not next(threads) then return cb(nil, failed) end
    for _, t in ipairs(vim.tbl_values(threads)) do
      table.sort(t.comments, function(a, b) return (a.ts or 0) < (b.ts or 0) end)
      local last = t.comments[#t.comments]
      t.ts, t.resolved = last.ts, last.resolved
      for _, c in ipairs(t.comments) do
        c.resolved = nil
      end
      items[#items + 1] = t
    end
    cb(items)
  end

  json(tea_api(("/repos/{owner}/{repo}/issues/%d/comments"):format(number)), root, function(rows, err)
    failed = failed or err
    for _, c in ipairs(rows or {}) do
      items[#items + 1] = {
        kind = "comment",
        id = c.id,
        author = vim.tbl_get(c, "user", "login") or "?",
        body = c.body or "",
        ts = fmt.epoch(c.created_at),
        url = c.html_url,
      }
    end
    settle()
  end)

  json(tea_api(("/repos/{owner}/{repo}/pulls/%d/reviews"):format(number)), root, function(rows, err)
    failed = failed or err
    local want = {}
    for _, r in ipairs(rows or {}) do
      local verdict = VERDICT[r.state]
      if verdict and not (verdict == "commented" and (r.body or "") == "") then
        items[#items + 1] = {
          kind = "review",
          id = r.id,
          verdict = verdict,
          dismissed = r.dismissed or nil,
          author = vim.tbl_get(r, "user", "login") or "?",
          body = r.body or "",
          ts = fmt.epoch(r.submitted_at),
          url = r.html_url,
        }
      end
      if (r.comments_count or 0) > 0 then want[#want + 1] = r.id end
    end
    if #want == 0 then return settle() end

    pending = pending + 1 -- the fan-out below is a third phase
    settle() -- close the review phase itself
    run.pump(want, function(id, land)
      json(tea_api(("/repos/{owner}/{repo}/pulls/%d/reviews/%d/comments"):format(number, id)), root, function(cs, e)
        failed = failed or e
        for _, c in ipairs(cs or {}) do
          local line = M.hunk_line(c.diff_hunk)
          local key = (c.path or "?") .. ":" .. tostring(line or c.position or 0)
          local t = threads[key]
          if not t then
            t = {
              kind = "thread",
              key = key,
              path = c.path,
              line = line,
              url = c.html_url,
              comments = {},
            }
            threads[key] = t
          end
          t.comments[#t.comments + 1] = {
            author = vim.tbl_get(c, "user", "login") or "?",
            body = c.body or "",
            ts = fmt.epoch(c.created_at),
            resolved = c.resolver ~= nil or nil,
          }
        end
        land()
      end)
    end, settle)
  end)
end

-- ----------------------------------------------------------------- public ---

--- The whole conversation of one PR.
---@param forge "gh"|"tea"
---@param number integer
---@param cb fun(items?: table[], err?: string)
function M.talk(root, forge, number, cb)
  if forge == "gh" then return gh_talk(root, number, cb) end
  tea_talk(root, number, cb)
end

return M
