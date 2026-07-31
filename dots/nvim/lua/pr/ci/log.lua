-- pr.ci.log: pr://job/{id} - one CI job's log, as a normal buffer.
--
-- The log format is the runner's, and Forgejo's act_runner is a port of
-- GitHub's: both emit `2026-07-31T18:23:10.7452532Z ` per line and the same
-- `##[group]` / `##[error]` markers (verified against Forgejo 16). So this
-- module is forge-agnostic and only pr.ci.api knows who answered.
--
-- Timestamps and markers are CONCEALED, not deleted: the buffer still holds
-- the real log, so a yank is the real line and gS reveals what was hidden.
-- Groups fold, and a running job re-reads itself until it stops.

local ansi = require "pr.ci.ansi"
local api = require "pr.ci.api"
local ci = require "pr.ci"
local data = require "pr.data"

local M = {}

local ns = vim.api.nvim_create_namespace "pr_ci_log"

local levels = {} ---@type table<integer, string[]>  bufnr -> per-line foldexpr
local timers = {} ---@type table<integer, uv.uv_timer_t>
local gens = {} ---@type table<integer, integer>

local CHUNK = 1000
local POLL = 5000
local TS = "^(%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d%.%d+Z )(.*)$"

local function warn(msg) vim.notify("pr: " .. msg, vim.log.levels.WARN) end

local function setup_hls()
  for group, link in pairs {
    PrCiGroup = "Title",
    PrCiCommand = "Directory",
    PrCiError = "DiagnosticError",
    PrCiWarn = "DiagnosticWarn",
    PrCiNotice = "DiagnosticInfo",
    PrCiMuted = "Comment",
  } do
    vim.api.nvim_set_hl(0, group, { link = link, default = true })
  end
end

-- ----------------------------------------------------------------- folds ---

--- 'foldexpr' backend. Levels are computed once at paint time; this only
--- reads them back, because a foldexpr runs for every line on every redraw.
function M.fold(lnum)
  local l = levels[vim.api.nvim_get_current_buf()]
  return l and l[lnum] or "0"
end

function M.foldtext()
  local line = vim.fn.getline(vim.v.foldstart)
  local text = line:gsub(TS, "%2"):gsub("##%[group%]", "")
  return ("  %s  (%d lines)"):format(vim.trim(text), vim.v.foldend - vim.v.foldstart)
end

-- ---------------------------------------------------------------- parsing ---

---@class pr.ci.log.Row
---@field text string      the raw line, timestamp and marker included
---@field fold string      foldexpr value
---@field hl string?       highlight for the whole line
---@field conceal integer  bytes of prefix to hide
---@field label string?    virtual word standing in for the hidden marker

--- Markers the runner writes inline. `##[endgroup]` is not a row: it is
--- where a fold ends, so it is dropped entirely.
local MARKERS = {
  ["##[group]"] = { fold = ">1", hl = "PrCiGroup" },
  ["##[error]"] = { hl = "PrCiError", label = "Error: " },
  ["##[warning]"] = { hl = "PrCiWarn", label = "Warning: " },
  ["##[notice]"] = { hl = "PrCiNotice", label = "Notice: " },
  ["##[command]"] = { hl = "PrCiCommand" },
  ["[command]"] = { hl = "PrCiCommand" },
}

---@param text string
---@return pr.ci.log.Row[]
function M.parse(text)
  local rows = {}
  local in_group = false
  for raw in (text .. "\n"):gmatch "([^\n]*)\n" do
    local stamp, body = raw:match(TS)
    body = body or raw
    local conceal = stamp and #stamp or 0

    local marker, spec
    for m, s in pairs(MARKERS) do
      if body:sub(1, #m) == m then
        marker, spec = m, s
        break
      end
    end

    if body:sub(1, #"##[endgroup]") == "##[endgroup]" then
      in_group = false
    elseif marker == "##[group]" then
      in_group = true
      rows[#rows + 1] = { text = raw, fold = ">1", hl = "PrCiGroup", conceal = conceal + #marker }
    elseif spec then
      rows[#rows + 1] = {
        text = raw,
        fold = in_group and "1" or "0",
        hl = spec.hl,
        conceal = conceal + #marker,
        label = spec.label,
      }
    elseif body ~= "" or #rows > 0 then
      rows[#rows + 1] = { text = raw, fold = in_group and "1" or "0", conceal = conceal }
    end
  end
  return rows
end

-- ------------------------------------------------------------------ paint ---

--- Chunked so a 20k-line log does not block the editor: each slice yields to
--- the event loop before the next. The ANSI state carries across slices, so
--- a colour opened in one is still open in the next.
local function paint(buf, gen, rows, done)
  local lines, meta, st, i = {}, {}, {}, 1
  local function slice()
    if not (vim.api.nvim_buf_is_valid(buf) and gens[buf] == gen) then return end
    local last = math.min(i + CHUNK - 1, #rows)
    for k = i, last do
      local text, spans, links = ansi.line(rows[k].text, st)
      lines[k] = text
      meta[k] = { spans = spans, links = links, row = rows[k] }
    end
    i = last + 1
    if i <= #rows then return vim.schedule(slice) end

    levels[buf] = {}
    for k, r in ipairs(rows) do
      levels[buf][k] = r.fold
    end

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.bo[buf].modified = false

    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    vim.api.nvim_buf_clear_namespace(buf, ansi.ns, 0, -1)
    for k, m in ipairs(meta) do
      local r = m.row
      if r.conceal > 0 then
        vim.api.nvim_buf_set_extmark(buf, ns, k - 1, 0, { end_col = math.min(r.conceal, #lines[k]), conceal = "" })
      end
      if r.label then
        vim.api.nvim_buf_set_extmark(buf, ns, k - 1, math.min(r.conceal, #lines[k]), {
          virt_text = { { r.label, r.hl } },
          virt_text_pos = "inline",
        })
      end
      if r.hl then
        vim.api.nvim_buf_set_extmark(buf, ns, k - 1, 0, { end_row = k, hl_group = r.hl, hl_eol = true, priority = 90 })
      end
      ansi.apply(buf, k - 1, m.spans, m.links, #lines[k])
    end
    done(lines)
  end
  slice()
end

-- ------------------------------------------------------------------- load ---

local function stop(buf)
  local t = timers[buf]
  if t then
    t:stop()
    if not t:is_closing() then t:close() end
    timers[buf] = nil
  end
end

local load

--- A running job is re-read until it stops. GitHub refuses a running job's
--- log outright (cli/cli#3484) and this shows the refusal until the job
--- finishes; Forgejo serves what the runner has written, so it tails.
local function watch(buf, root, job)
  stop(buf)
  if job.bucket ~= "running" and job.bucket ~= "pending" then return end
  local t = assert(vim.uv.new_timer())
  timers[buf] = t
  t:start(
    POLL,
    POLL,
    vim.schedule_wrap(function()
      if not (vim.api.nvim_buf_is_valid(buf) and #vim.fn.win_findbuf(buf) > 0) then return stop(buf) end
      load(buf, root, job, true)
    end)
  )
end

--- Fetch and paint. `keep` holds the cursor and scroll, which is what a poll
--- and an explicit R both want; only the first load jumps to the failure.
function load(buf, root, job, keep)
  gens[buf] = (gens[buf] or 0) + 1
  local gen = gens[buf]
  local views = {}
  for _, w in ipairs(vim.fn.win_findbuf(buf)) do
    views[w] = vim.api.nvim_win_call(w, vim.fn.winsaveview)
  end

  api.job_log(root, data.forge(root), job.id, function(text, err)
    if not (vim.api.nvim_buf_is_valid(buf) and gens[buf] == gen) then return end
    if not text then
      if not keep then
        vim.bo[buf].modifiable = true
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
          ("  no log for %s"):format(job.name or "this job"),
          "  " .. (err or "?"),
          "",
          job.bucket == "running" and "  the job is still running; this buffer refreshes itself" or "",
        })
        vim.bo[buf].modifiable = false
      end
      return watch(buf, root, job)
    end
    paint(buf, gen, M.parse((text:gsub("^\239\187\191", ""))), function(lines)
      for w, v in pairs(views) do
        if vim.api.nvim_win_is_valid(w) then vim.api.nvim_win_call(w, function() vim.fn.winrestview(v) end) end
      end
      if not keep then
        -- Land on the first error the way ci.nvim does: a log is opened to
        -- find out what broke, and scrolling to it by hand is the whole
        -- reason people paste CI logs into a pager.
        for k = 1, #lines do
          if levels[buf] and lines[k]:find "##%[error%]" then
            for _, w in ipairs(vim.fn.win_findbuf(buf)) do
              pcall(vim.api.nvim_win_set_cursor, w, { k, 0 })
              vim.api.nvim_win_call(w, function() vim.cmd "silent! normal! zv" end)
            end
            break
          end
        end
      end
      watch(buf, root, job)
    end)
  end)
end

-- ------------------------------------------------------------------- open ---

---@param dir 1|-1
local function step(dir)
  local buf = vim.api.nvim_get_current_buf()
  local l = levels[buf] or {}
  local cur = vim.fn.line "."
  local from, to, by = cur + 1, #l, 1
  if dir == -1 then
    from, to, by = cur - 1, 1, -1
  end
  for k = from, to, by do
    if l[k] == ">1" then
      vim.cmd "normal! m'"
      vim.api.nvim_win_set_cursor(0, { k, 0 })
      return vim.cmd "silent! normal! zv"
    end
  end
end

--- gS: uncover what is concealed. The buffer always held the raw log; this
--- is the switch that stops hiding it.
local function timestamps() vim.wo.conceallevel = vim.wo.conceallevel == 0 and 3 or 0 end

local HELP = {
  { "g?", "this help" },
  { "]] / [[", "next / prev group" },
  { "zR / zM", "open / close all groups" },
  { "gS", "show the raw timestamps and markers" },
  { "R / :e", "refresh now" },
  { "q", "back" },
}

---@param job table  a job from the pr.ci store
function M.open(root, job)
  if not job.id then return warn "this check has no log" end
  setup_hls()
  local name = ("pr://job/%d"):format(job.id)
  local buf = vim.fn.bufnr(name)
  if buf == -1 then
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, name)
  end
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modeline = false
  vim.bo[buf].undolevels = -1
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "prjob"

  local o = { buffer = buf, silent = true }
  vim.keymap.set("n", "]]", function() step(1) end, o)
  vim.keymap.set("n", "[[", function() step(-1) end, o)
  vim.keymap.set("n", "gS", timestamps, o)
  vim.keymap.set("n", "R", function() load(buf, root, job, true) end, o)
  vim.keymap.set("n", "q", "<cmd>silent! buffer #<cr>", o)
  vim.keymap.set("n", "g?", function() require("pr.fmt").help(" pr job ", HELP) end, o)

  vim.api.nvim_win_set_buf(0, buf)
  -- Window-local, so they are set here rather than off a FileType autocmd:
  -- the window is only known once the buffer is in it.
  vim.wo[0][0].wrap = false
  vim.wo[0][0].number = false
  vim.wo[0][0].conceallevel = 3
  vim.wo[0][0].concealcursor = "nvic"
  vim.wo[0][0].foldenable = true
  vim.wo[0][0].foldmethod = "expr"
  vim.wo[0][0].foldlevel = 0
  vim.wo[0][0].foldexpr = 'v:lua.require("pr.ci.log").fold(v:lnum)'
  vim.wo[0][0].foldtext = 'v:lua.require("pr.ci.log").foldtext()'
  vim.wo[0][0].winbar = (" %s  %s"):format(
    ("%%#%s#%s%%*"):format(ci.HL[job.bucket] or "Comment", ci.SYM[job.bucket] or "?"),
    (job.name or "job"):gsub("%%", "%%%%")
  )

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "  loading log..." })
  vim.bo[buf].modifiable = false
  load(buf, root, job, false)
end

vim.api.nvim_create_autocmd("BufWipeout", {
  group = vim.api.nvim_create_augroup("pr_ci_log", { clear = true }),
  pattern = "pr://job/*",
  callback = function(a)
    stop(a.buf)
    levels[a.buf], gens[a.buf] = nil, nil
  end,
})

return M
