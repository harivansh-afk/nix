-- pr.surface: the thing pr://list and pr://log both ARE.
--
-- Both are the same object: a read-only pr:// buffer holding one row per
-- item, columns re-flowed from the window width, painted wholesale from a
-- fresh render, fed by an async fetch that may land after the user has
-- already asked for another one. Only the rows and the verbs differ.
--
-- So everything structural lives here - buffer identity, options, the resize
-- re-render, the paint, the generation guard - and a surface owner supplies
-- just `render`, its keys, and its help. Adding a third surface should be
-- rows plus keys, nothing else.
--
-- Not here: anything that knows what a row MEANS. Stacking is pr.list's,
-- commit ranges are pr.log's. This file has no idea what it is drawing.

local fmt = require "pr.fmt"

local M = {}

-- ------------------------------------------------------------------- orb ---

--- CI state as a coloured orb. Plain UTF-8 - no icon font required (nonicons
--- glyphs are PUA codepoints that collide with Nerd Fonts: hello bluetooth).
---
--- Takes a pr.ci BUCKET - the rollup off a store entry - so the orb and the
--- pane read the very same word and can never disagree about what green
--- means. The orb has two shapes where the pane has six glyphs: hollow means
--- nothing has produced a result yet (no CI at all, or still queued), filled
--- means something has. Colour separates the hollow pair (grey nothing,
--- yellow queued) and carries the pane's palette for the filled ones.
---@param bucket string? pr.ci bucket, nil = no CI at all
---@return string glyph, string hl
function M.orb(bucket)
  if not bucket then return "○", "Comment" end
  if bucket == "pending" then return "○", "DiagnosticWarn" end
  return "●", require("pr.ci").HL[bucket]
end

-- ---------------------------------------------------------------- columns ---

--- Cells actually available for text in the window showing `buf`, discounting
--- the gutter (number column, signs, folds). Falls back to the whole screen
--- width when the buffer is not on screen, so a render that happens while
--- hidden still produces sane columns.
---@return integer
function M.width(buf)
  local win = buf and vim.fn.bufwinid(buf) or -1
  if win == -1 then return vim.o.columns end
  return vim.api.nvim_win_get_width(win) - vim.fn.getwininfo(win)[1].textoff
end

--- The fzf-picker-era column split both surfaces use: a fixed left column, a
--- title that absorbs whatever is left, then author and age right-aligned
--- against the window edge.
---@param width integer  cells available (M.width)
---@param left integer   cells the leading orb + left column occupy
---@return integer title_w
function M.title_width(width, left)
  local author_w, age_w, gap = 16, 4, 2
  return math.max(20, width - left - author_w - age_w - 3 * gap)
end

M.AUTHOR_W, M.AGE_W = 16, 4

-- ---------------------------------------------------------------- refresh ---

--- R and <c-r>, on every pr:// buffer, each meaning exactly what `:e` means
--- there: the list re-fetches, pr://files re-reads its PR from origin, the
--- log pulls, the checks pane asks the forge again.
---
--- <c-r> is redo, which is dead in a non-modifiable nofile buffer, and these
--- maps are buffer-local, so redo everywhere else is untouched.
---@param buf integer
---@param fn fun()
function M.refresh_keys(buf, fn)
  for _, key in ipairs { "R", "<c-r>" } do
    vim.keymap.set("n", key, fn, { buffer = buf, silent = true, desc = "pr: refresh" })
  end
end

--- What the three PR buffers share - pr://list, pr://log and pr://files, the
--- last of which is not a pr.Surface: the verbs, the marks, and refresh.
--- Attached before a surface's own keys, so a surface can still override one
--- (pr://log does that for O). The CI buffers take refresh alone; their
--- subject is a job, not a PR.
---@param buf integer
---@param refresh fun()
function M.common_keys(buf, refresh)
  require("pr.verbs").attach(buf)
  require("pr.marks").attach(buf)
  M.refresh_keys(buf, refresh)
end

--- The help rows those shared keys are worth, appended to a surface's own.
--- <leader>1-9 is global rather than a buffer key, so it is named here
--- rather than in marks' M.KEYS.
---@return {[1]:string,[2]:string}[]
function M.common_help()
  local rows = {}
  for _, mod in ipairs { require "pr.verbs", require "pr.marks" } do
    for _, k in ipairs(mod.KEYS) do
      rows[#rows + 1] = { k[1], k[3] }
    end
  end
  rows[#rows + 1] = { "<leader>1-9", "jump to a marked slot" }
  rows[#rows + 1] = { "<c-e>", "the whole fast list, in a float" }
  return rows
end

-- --------------------------------------------------------------- surfaces ---

---@class pr.Surface
---@field name string    buffer name, e.g. "pr://log"
---@field ns integer     highlight namespace
---@field buf integer?   nil until first opened
---@field gen integer    generation counter, for dropping stale async replies

local Surface = {}
Surface.__index = Surface

--- Declare a surface. Nothing is created until :ensure.
---@param spec {name:string, filetype:string, title:string, help:table, render:fun(), refresh:fun(), keys:fun(buf:integer)}
---@return pr.Surface
function M.new(spec)
  return setmetatable({
    name = spec.name,
    filetype = spec.filetype,
    title = spec.title,
    help_rows = spec.help,
    render = spec.render,
    refresh = spec.refresh,
    keys = spec.keys,
    ns = vim.api.nvim_create_namespace("pr_" .. spec.filetype),
    buf = nil,
    gen = 0,
  }, Surface)
end

function Surface:valid() return self.buf ~= nil and vim.api.nvim_buf_is_valid(self.buf) end

--- g? - the fugitive gesture. The shared rows are appended from the modules
--- that own those keys, so no two surfaces can drift on what one does.
function Surface:help()
  local rows = vim.deepcopy(self.help_rows)
  vim.list_extend(rows, M.common_help())
  fmt.help(self.title, rows)
end

--- `:e pr://log` in a fresh session lands nvim on a brand new buffer already
--- wearing that name; creating our own on top would be a duplicate name
--- (E95). Adopt whatever buffer is already there instead.
function Surface:ensure()
  if self:valid() then return end
  local cur = vim.api.nvim_get_current_buf()
  local adopt = vim.api.nvim_buf_get_name(cur):match(vim.pesc(self.name) .. "$") ~= nil
  self.buf = adopt and cur or vim.api.nvim_create_buf(false, true)
  if not adopt then vim.api.nvim_buf_set_name(self.buf, self.name) end

  local b = self.buf
  vim.bo[b].buftype = "nofile"
  vim.bo[b].bufhidden = "hide"
  vim.bo[b].swapfile = false
  vim.bo[b].filetype = self.filetype
  vim.bo[b].modifiable = false

  -- Columns derive from the window width: re-flow when that changes, or when
  -- the buffer is re-shown in a differently sized window.
  local grp = vim.api.nvim_create_augroup("pr_" .. self.filetype .. "_layout", { clear = true })
  vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
    group = grp,
    callback = function()
      if self:valid() and vim.fn.bufwinid(self.buf) ~= -1 then self.render() end
    end,
  })
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = grp,
    buffer = b,
    callback = function() self.render() end,
  })

  local o = { buffer = b, silent = true }
  vim.keymap.set("n", "g?", function() self:help() end, o)
  vim.keymap.set("n", "q", "<cmd>silent! buffer #<cr>", o)
  -- Shared keys first, surface keys second, so a surface can OVERRIDE one.
  -- pr://log needs that for O: the verb opens a PR page, and a commit row has
  -- no PR - it wants /commit/<sha> instead.
  M.common_keys(b, self.refresh)
  self.keys(b)
end

--- Put the surface in the current window, if it is not already there.
function Surface:show()
  if vim.api.nvim_get_current_buf() ~= self.buf then vim.api.nvim_win_set_buf(0, self.buf) end
end

--- Replace the buffer wholesale. A render is a LOAD, never an edit, so
--- 'modified' is cleared too - `:e` checks it before reloading.
---@param lines string[]
---@param marks {[1]:integer,[2]:integer,[3]:integer,[4]:string}[] row, from, to, group
function Surface:paint(lines, marks)
  if not self:valid() then return end
  local b = self.buf
  vim.bo[b].modifiable = true
  vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
  vim.bo[b].modifiable = false
  vim.bo[b].modified = false
  vim.api.nvim_buf_clear_namespace(b, self.ns, 0, -1)
  for _, m in ipairs(marks) do
    vim.api.nvim_buf_set_extmark(b, self.ns, m[1], m[2], { end_col = m[3], hl_group = m[4] })
  end
end

--- A segmenter writing into `lines`/`marks` in the positional order :paint
--- expects. Offsets come from the text actually emitted, so a resized column
--- cannot silently shift every highlight after it (see pr.fmt.segmenter).
function M.segmenter(lines, marks)
  return fmt.segmenter(lines, marks, function(row, group, from, to) return { row, from, to, group } end)
end

function Surface:placeholder(text) self:paint({ " " .. text }, {}) end

--- Bump the generation and hand back the new value. An async reply carrying a
--- stale one is a reply to a question the user has already re-asked, and is
--- dropped rather than painted over the newer answer.
function Surface:bump()
  self.gen = self.gen + 1
  return self.gen
end

--- Is this reply still wanted, and is there still a buffer to paint it into?
function Surface:current(gen) return gen == self.gen and self:valid() end

function Surface:width() return M.width(self.buf) end

return M
