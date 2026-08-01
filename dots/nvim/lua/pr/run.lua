-- pr.run: the process engine - every subprocess in this plugin starts here.
--
-- One place owns how an external command is spawned, cached, awaited and
-- fanned out; pr.data (git and PR metadata) and pr.ci.api (forge CI) own only
-- WHAT to ask and how to read the answer. Before this file each of them
-- carried its own copy of the runner, and the copies had started to drift.
--
-- Four primitives:
--   git    sync git read           - blocks, for answers a render needs NOW
--   spawn  start filling a cache slot in the background (fugitive's move)
--   await  the sync read of a slot, riding the in-flight job
--   sh     async subprocess -> stdout        (json: -> decoded table)
--   pump   bounded parallel fan-out, the shape every N-of-M fetch takes

local M = {}

-- -------------------------------------------------------------------- git ---

--- Global flags on EVERY git call, stolen from fugitive's status runner:
--- never take the optional index lock for a read, and never octal-quote
--- non-ASCII paths (paths must match buffer rows byte-for-byte).
local GIT = { "git", "--no-optional-locks", "-c", "core.quotePath=false" }

---@param args string[]
---@return string[]? lines, string? err
function M.git(args)
  local out = vim.fn.systemlist(vim.list_extend(vim.deepcopy(GIT), args))
  if vim.v.shell_error ~= 0 then return nil, table.concat(out or {}, "\n") end
  return out
end

-- ------------------------------------------------------------ spawn/await ---
-- Fugitive's core perf move (fugitive#Execute + fugitive#Wait): START a git
-- call the moment it is known to be needed, BLOCK only when the answer is
-- consumed. spawn() begins filling a cache slot in the background; await()
-- is the sync read, riding an in-flight job instead of forking a second
-- process. Slots are immutable answers keyed on resolved shas by the caller,
-- so the cap is a memory valve, never a correctness requirement.

local cache, cache_n = {}, 0
local CACHE_MAX = 512

local jobs = {} ---@type table<string, {obj: vim.SystemObj, settle: fun(r: vim.SystemCompleted)}>

local function put(key, val)
  if cache_n >= CACHE_MAX then
    cache, cache_n = {}, 0
  end
  cache[key], cache_n = val, cache_n + 1
  return val
end

---@param key string cache slot the job fills
---@param args string[] git args
---@param parse fun(lines: string[]): any pure Lua - on_exit is a fast context
function M.spawn(key, args, parse)
  if cache[key] ~= nil or jobs[key] then return end
  local job = {}
  job.settle = function(r)
    if jobs[key] ~= job then return end -- M.clear dropped this job
    jobs[key] = nil
    if r.code == 0 then put(key, parse(vim.split(r.stdout or "", "\n", { trimempty = true }))) end
  end
  jobs[key] = job
  job.obj = vim.system(vim.list_extend(vim.deepcopy(GIT), args), { text = true }, job.settle)
end

--- Cache read that first waits for (and settles) the in-flight job, if any.
--- settle is idempotent, so racing git's own on_exit is harmless.
function M.await(key)
  local job = jobs[key]
  if job then job.settle(job.obj:wait()) end
  return cache[key]
end

function M.clear()
  cache, cache_n, jobs = {}, 0, {}
end

-- ------------------------------------------------------------------ async ---

--- Async subprocess -> stdout. Failures come back as ONE error string: both
--- forge CLIs answer API failures with a JSON body carrying `message`, so
--- that is unwrapped here and no caller ever parses an error twice.
---@param cmd string[]
---@param root string  cwd
---@param cb fun(out?: string, err?: string)
function M.sh(cmd, root, cb)
  vim.system(cmd, { cwd = root, text = true }, function(r)
    vim.schedule(function()
      if r.code ~= 0 then
        local e = vim.trim(r.stderr or "")
        if e == "" then e = vim.trim(r.stdout or "") end
        local ok, body = pcall(vim.json.decode, e)
        if ok and type(body) == "table" and body.message then e = body.message end
        return cb(nil, e ~= "" and e or ("exited with code " .. r.code))
      end
      cb(r.stdout or "")
    end)
  end)
end

--- M.sh, decoded. luanil both ways: a JSON null must never become vim.NIL in
--- a table a consumer iterates.
---@param cb fun(data?: table, err?: string)
function M.json(cmd, root, cb)
  M.sh(cmd, root, function(out, err)
    if err then return cb(nil, err) end
    local ok, decoded = pcall(vim.json.decode, out, { luanil = { object = true, array = true } })
    if not ok or type(decoded) ~= "table" then return cb(nil, "malformed JSON from the forge") end
    cb(decoded)
  end)
end

-- ------------------------------------------------------------------- pump ---

--- How many async items may be in flight at once. The forge answers parallel
--- requests happily - measured on Forgejo 16, 20 per-sha calls took 0.89s
--- fanned out against 3.57s sequentially - but one OS process per item is a
--- real cost on the nvim side, and a 100-row surface would spawn 100 of them.
--- Eight keeps the win (the calls, not the processes, are the latency)
--- without ever holding more than a handful of children alive.
local LANES = 8

--- Bounded parallel fan-out. `each(item, land)` starts one item's work and
--- calls `land()` exactly once when it settles; results flow through whatever
--- side channel the caller closed over. Progress is INCREMENTAL by
--- construction - each item lands on its own, nothing waits for the slowest.
---@generic T
---@param items T[]
---@param each fun(item: T, land: fun())
---@param done? fun()
function M.pump(items, each, done)
  local total = #items
  if total == 0 then
    if done then done() end
    return
  end
  local next_i, live, finished = 1, 0, 0
  local function fill()
    while live < LANES and next_i <= total do
      local item = items[next_i]
      next_i, live = next_i + 1, live + 1
      local landed = false
      each(item, function()
        if landed then return end -- a double land must not corrupt the counts
        landed = true
        live, finished = live - 1, finished + 1
        if finished == total then
          if done then done() end
          return
        end
        fill()
      end)
    end
  end
  fill()
end

return M
