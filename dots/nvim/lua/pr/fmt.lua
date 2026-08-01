-- pr.fmt: small presentation helpers shared by the pr surfaces.
--
-- Truncation and padding go by DISPLAY width, not bytes - "…" is 3 bytes but
-- 1 cell, and byte-based %-Ns padding scatters every column after a
-- multibyte char.

local M = {}

local ns = vim.api.nvim_create_namespace "pr_fmt"

--- Returns a `seg(segs)` that appends ONE line built from { text, group? }
--- segments to `lines`, and one record per highlighted segment to `marks`.
---
--- The point is that offsets are computed from the text actually emitted and
--- never hand-counted, so inserting or resizing a column cannot silently
--- shift every highlight after it.
---
--- `mark` builds the record because the two surfaces store a highlight
--- differently - pr.list orders it by position, pr.view by group - and that
--- tuple shape is the caller's business, not this helper's.
---@param lines string[] accumulator, appended one entry per `seg` call
---@param marks any[] accumulator, appended one entry per highlighted segment
---@param mark fun(row:integer, group:string, from:integer, to:integer):any
---@return fun(segs: {[1]:string,[2]:string?}[])
function M.segmenter(lines, marks, mark)
  return function(segs)
    local text, off = {}, 0
    for _, sg in ipairs(segs) do
      text[#text + 1] = sg[1]
      if sg[2] then marks[#marks + 1] = mark(#lines, sg[2], off, off + #sg[1]) end
      off = off + #sg[1]
    end
    lines[#lines + 1] = table.concat(text)
  end
end

function M.trunc(str, w)
  if vim.fn.strdisplaywidth(str) > w then
    while vim.fn.strdisplaywidth(str) > w - 1 do
      str = vim.fn.strcharpart(str, 0, vim.fn.strchars(str) - 1)
    end
    str = str .. "…"
  end
  return str
end

function M.ljust(str, w)
  str = M.trunc(str, w)
  return str .. string.rep(" ", w - vim.fn.strdisplaywidth(str))
end

function M.rjust(str, w)
  str = M.trunc(str, w)
  return string.rep(" ", w - vim.fn.strdisplaywidth(str)) .. str
end

--- ISO-8601 -> TRUE unix epoch. THE time conversion in this plugin: every
--- age and every duration is a subtraction of two true epochs, and nothing
--- outside this function ever parses a timestamp.
---
--- Lua has no portable "UTC fields -> epoch", only os.time, which reads its
--- table as LOCAL calendar time. So the fields go through os.time anyway,
--- and the resulting shift is measured and removed on the spot: misread the
--- CURRENT UTC fields the same way, and the difference between that and the
--- real os.time() is exactly the shift (both misreadings are the same
--- constant, so it cancels to the true epoch). This plugin once kept the
--- shift IN and compared "skewed vs skewed" - which was exact right up until
--- a true epoch from git's %at met the skewed now, and every commit age came
--- out 8 hours old(er). One frame, true unix time, no cleverness.
---
--- isdst=false pins both misreadings to standard time; without it mktime
--- GUESSES DST per date and summer timestamps land an hour off.
---
--- The trailing offset is honoured when present: GitHub emits Z, but
--- Gitea/Forgejo emit the server's local offset ("+02:00") - dropping it
--- would skew every age by the server's timezone.
---@param iso string?
---@return integer? epoch
function M.epoch(iso)
  local y, mo, d, h, mi, sec = (iso or ""):match "(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)"
  if not y then return nil end
  local as_utc = os.time { year = y, month = mo, day = d, hour = h, min = mi, sec = sec, isdst = false }
  local shift = os.time() - os.time(os.date "!*t") -- true now minus misread-UTC now
  local epoch = as_utc + shift
  local sign, oh, om = (iso or ""):match "T[%d:%.]+([+-])(%d%d):?(%d%d)"
  if sign then epoch = epoch - (sign == "-" and -1 or 1) * (tonumber(oh) * 3600 + tonumber(om) * 60) end
  return epoch
end

--- "3d" from an ISO-8601 timestamp: parse, then age.
function M.ago(iso) return M.since(M.epoch(iso)) end

--- The compact age of a true epoch - git's `%at`, or M.epoch's output.
---
--- The NUMBER is git's, exactly: this is git date.c's relative-date ladder,
--- each rung rounding to nearest (+half-unit before the divide), so a commit
--- `git log` calls "25 hours ago" reads 25h here and "2 days ago" reads 2d -
--- never a floor-vs-round disagreement with the terminal one pane over. Only
--- the suffix is compacted, because the age column has four cells and
--- "25 hours ago" does not fit any column worth having.
---@param epoch integer? seconds
---@return string
function M.since(epoch)
  if not epoch then return "" end
  local dt = math.max(0, os.time() - epoch)
  if dt < 90 then return dt .. "s" end
  local m = math.floor((dt + 30) / 60)
  if m < 90 then return m .. "m" end
  local h = math.floor((m + 30) / 60)
  if h < 36 then return h .. "h" end
  local d = math.floor((h + 12) / 24)
  if d < 14 then return d .. "d" end
  local w = math.floor((d + 3) / 7)
  if w < 10 then return w .. "w" end
  local mo = math.floor((d + 15) / 30)
  if mo < 12 then return mo .. "mo" end
  return math.floor((d + 183) / 365) .. "y"
end

--- g? - the fugitive gesture: a small float over the cursor, keys
--- highlighted in fugitiveHelpTag like fugitive's own help column.
---@param title string
---@param entries {[1]:string,[2]:string}[] key, description
function M.help(title, entries)
  local keyw, width = 0, 0
  for _, h in ipairs(entries) do
    keyw = math.max(keyw, #h[1])
  end
  local lines = {}
  for _, h in ipairs(entries) do
    lines[#lines + 1] = (" %-" .. keyw .. "s  %s"):format(h[1], h[2])
    width = math.max(width, #lines[#lines])
  end
  local b = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
  vim.bo[b].modifiable = false
  vim.bo[b].bufhidden = "wipe"
  for i, h in ipairs(entries) do
    vim.api.nvim_buf_set_extmark(b, ns, i - 1, 1, { end_col = 1 + #h[1], hl_group = "fugitiveHelpTag" })
  end
  local win = vim.api.nvim_open_win(b, true, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = width + 1,
    height = #lines,
    style = "minimal",
    border = "single",
    title = title,
    title_pos = "center",
  })
  for _, k in ipairs { "q", "<Esc>", "g?" } do
    vim.keymap.set("n", k, "<cmd>close<cr>", { buffer = b, silent = true, nowait = true })
  end
  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = b,
    once = true,
    callback = function()
      if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    end,
  })
end

return M
