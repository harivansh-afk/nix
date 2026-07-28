-- pr.view: THE surface for PR review - a fugitive-status style files buffer.
--
-- One row per file ("M path", letter semantics identical to fugitive),
-- <Tab>/= expands the file's hunks inline, <CR> opens the full diffs.nvim
-- review at that file. The buffer is a pure function of require("pr").state
-- plus the `expanded` set: every change rebuilds it wholesale.
--
-- diffs.nvim decoration: rows are exactly "M path" because its parser's
-- FIRST filename pattern is the fugitive form `^[MADRCU?!]%s+(.+)$` - clean
-- rows give every expanded hunk correct treesitter language highlighting.
-- Stats live in right-aligned virtual text so they never pollute the row.
--
-- Colors are fugitive's, exactly: every group here routes through the
-- fugitive* highlight groups (declared below with fugitive's own default
-- links), so the buffer is indistinguishable from a :Git status palette
-- and follows any colorscheme that themes fugitive.

local data = require "pr.data"
local gitstats = require "gitstats"

local M = {}

local ns = vim.api.nvim_create_namespace "pr_view"
local buf = nil ---@type integer?
local attached = false
local expanded = {} ---@type table<string, true> -- survives commit hops on purpose
local line_map = {} ---@type table<integer, string> -- lnum -> owning file path
local file_rows = {} ---@type table<string, integer> -- path -> its row lnum

local function state() return require("pr").state end

function M.active() return buf ~= nil and vim.api.nvim_get_current_buf() == buf end

-- ------------------------------------------------------------ highlights ---

--- fugitive's exact hi-def-link table (syntax/fugitive.vim), declared with
--- default=true: the view renders IDENTICALLY to a :Git status buffer even
--- before fugitive's syntax ever loads, real fugitive links are no-ops on
--- top of these, and a colorscheme that themes fugitive restyles this view
--- for free.
local FUGITIVE_LINKS = {
  fugitiveHeader = "Label",
  fugitiveHelpHeader = "fugitiveHeader",
  fugitiveHelpTag = "Tag",
  fugitiveHeading = "PreProc",
  fugitiveUntrackedHeading = "PreCondit",
  fugitiveUnstagedHeading = "Macro",
  fugitiveStagedHeading = "Include",
  fugitiveModifier = "Type",
  fugitiveUntrackedModifier = "StorageClass",
  fugitiveUnstagedModifier = "Structure",
  fugitiveStagedModifier = "Typedef",
  fugitiveHash = "Identifier",
  fugitiveSymbolicRef = "Function",
  fugitiveCount = "Number",
}

--- Letter -> the fugitive modifier group that letter wears in a fugitive
--- status buffer. fugitive colors by SECTION, not letter; a PR file list has
--- one section, so each letter takes the group of the section it lives in
--- in practice: M/R/C sit in Unstaged (Structure), A lands in Staged
--- (Typedef), D/? borrow Untracked (StorageClass) to stay distinct without
--- leaving fugitive's palette. Anything else falls back to fugitiveModifier.
local MOD_HL = {
  M = "fugitiveUnstagedModifier",
  R = "fugitiveUnstagedModifier",
  C = "fugitiveUnstagedModifier",
  A = "fugitiveStagedModifier",
  D = "fugitiveUntrackedModifier",
  ["?"] = "fugitiveUntrackedModifier",
}

--- Stat colors (GitStatAdd/GitStatDel) come from gitstats - the ONE module
--- defining the "+N -N" identity shared with the fugitive status buffer.
local function setup_hls()
  vim.api.nvim_set_hl(0, "diffLine", { link = "Statement", default = true })

  for group, link in pairs(FUGITIVE_LINKS) do
    vim.api.nvim_set_hl(0, group, { link = link, default = true })
  end

  gitstats.setup_hls()
end

-- ---------------------------------------------------------------- render ---

---@param keep? string  path to keep the cursor on
function M.render(keep)
  local s = state()
  local c = s.commits[s.idx]
  if not (buf and c) then return end

  setup_hls()
  -- Resolve the base ref ONCE per render: diff caches key on shas, so an
  -- externally moved origin/<base> invalidates them without any bookkeeping.
  local base_sha = s.mode == "cumulative" and data.resolve(s.root, s.base) or nil
  local files = data.files(s.root, s.base, c.sha, s.mode, base_sha)
  local has_diffs = (pcall(require, "diffs"))

  local lines, hl, vt = {}, {}, {}
  line_map, file_rows = {}, {}

  --- Build a line from { text, group? } segments; offsets computed, never
  --- hand-counted.
  ---@param segs {[1]:string,[2]:string?}[]
  local function seg(segs)
    local text, off = {}, 0
    for _, sg in ipairs(segs) do
      text[#text + 1] = sg[1]
      if sg[2] then hl[#hl + 1] = { #lines, sg[2], off, off + #sg[1] } end
      off = off + #sg[1]
    end
    lines[#lines + 1] = table.concat(text)
  end

  seg { { "PR:", "fugitiveHeader" }, { "     " }, { "#" .. s.pr.number, "fugitiveCount" }, { " " }, { s.pr.title or "" } }
  seg {
    { "Commit:", "fugitiveHeader" },
    { " " },
    { c.sha, "fugitiveHash" },
    { " " },
    { c.subject },
  }
  seg {
    { "Base:", "fugitiveHeader" },
    { "   " },
    { s.base or "", "fugitiveSymbolicRef" },
  }
  seg {
    { "Mode:", "fugitiveHeader" },
    { "   " },
    { s.mode, "fugitiveSymbolicRef" },
    { " (" },
    { ("%d/%d"):format(s.idx, #s.commits), "fugitiveCount" },
    { ")" },
  }
  seg { { "Help:", "fugitiveHelpHeader" }, { "   " }, { "g?", "fugitiveHelpTag" } }
  lines[#lines + 1] = ""
  -- Fugitive-bare heading: change totals live ONLY in the per-file virtual
  -- text, never duplicated up here.
  seg {
    { "Files", "fugitiveHeading" },
    { " (" },
    { tostring(#files), "fugitiveCount" },
    { ")" },
  }

  for _, f in ipairs(files) do
    local name = f.old_path and (f.old_path .. " -> " .. f.path) or f.path
    seg { { f.status, MOD_HL[f.status] or "fugitiveModifier" }, { " " }, { name } } -- modifier + plain path
    local row = #lines
    line_map[row], file_rows[f.path] = f.path, row
    vt[#vt + 1] = { row - 1, gitstats.virt(f.add, f.del, f.binary) }

    if expanded[f.path] then
      for _, l in ipairs(data.file_diff(s.root, s.base, c.sha, s.mode, f.path, base_sha)) do
        local at = l:match "^@@+.-@@+"
        -- Drop git's xfuncname context from hunk headers: the marker line is
        -- a delimiter, code belongs to the hunk body below it.
        if at then l = at end
        lines[#lines + 1] = l
        line_map[#lines] = f.path
        if at then
          hl[#hl + 1] = { #lines - 1, "diffLine", 0, #at }
        elseif not has_diffs then
          -- Flat fallback ONLY without diffs.nvim - never fight its treesitter.
          local ch = l:sub(1, 1)
          local g = ch == "+" and "GitStatAdd" or ch == "-" and "GitStatDel" or nil
          if g then hl[#hl + 1] = { #lines - 1, g, 0, -1 } end
        end
      end
      lines[#lines + 1] = ""
    end
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, h in ipairs(hl) do
    local end_col = h[4] == -1 and #lines[h[1] + 1] or h[4]
    vim.api.nvim_buf_set_extmark(buf, ns, h[1], h[3], { end_col = end_col, hl_group = h[2] })
  end
  for _, v in ipairs(vt) do
    vim.api.nvim_buf_set_extmark(buf, ns, v[1], 0, { virt_text = v[2], virt_text_pos = "right_align" })
  end

  local diffs_ok, diffs = pcall(require, "diffs")
  if diffs_ok then
    -- diffs.nvim's parser reads b:diffs_repo_root to resolve filetypes (open
    -- buffers, then filename, then file CONTENT under the root) - without it
    -- the treesitter + intra-line diffing falls back to cwd guessing.
    vim.b[buf].diffs_repo_root = s.root
    if attached then
      diffs.refresh(buf)
    else
      diffs.attach(buf)
      attached = true
    end
  end

  local target = keep and file_rows[keep]
  if target then vim.api.nvim_win_set_cursor(0, { target, 0 }) end
end

-- --------------------------------------------------------------- actions ---

local function toggle()
  local path = line_map[vim.fn.line "."]
  if not path then return end
  expanded[path] = not expanded[path] and true or nil
  M.render(path)
end

--- New-file line for a cursor row inside an expanded hunk, nil elsewhere.
--- Walk up to the owning @@ header, then count new-side rows (context and
--- '+'; '-' rows do not exist in the new file) down to the cursor.
local function hunk_line(row, path)
  local frow = file_rows[path]
  if not (frow and buf) or row <= frow then return nil end
  local lines = vim.api.nvim_buf_get_lines(buf, frow, row, false) -- rows frow+1..row
  for i = #lines, 1, -1 do
    local start = lines[i]:match "^@@+ %-%d+,?%d* %+(%d+)"
    if start then
      if i == #lines then return tonumber(start) end -- cursor ON the header
      local n = 0
      for j = i + 1, #lines do
        if lines[j]:sub(1, 1) ~= "-" then n = n + 1 end
      end
      -- A '-' row has no new-side self: land on the first line after it.
      return tonumber(start) + n - (lines[#lines]:sub(1, 1) ~= "-" and 1 or 0)
    end
  end
  return nil
end

--- Full diffs.nvim review of the current range, jumped to this file - and,
--- from inside an expanded hunk, to this line. review_goto only takes a
--- file key (no line targeting in diffs.nvim), but the review split shows
--- real file content, so landing is a plain cursor move after the switch.
local function dive()
  local row = vim.fn.line "."
  local path = line_map[row]
  if not path then return end
  local lnum = hunk_line(row, path)
  local s = state()
  local c = s.commits[s.idx]
  local ok, commands = pcall(require, "diffs.commands")
  if not (ok and c) then return end
  commands.review(data.spec(s.root, s.base, c.sha, s.mode))
  vim.schedule(function()
    pcall(require("diffs").review_goto, path)
    if lnum then
      vim.schedule(function()
        pcall(vim.api.nvim_win_set_cursor, 0, { lnum, 0 })
        vim.cmd "silent! normal! zvzz"
      end)
    end
  end)
end

--- g? - the fugitive gesture. A small float over the cursor, keys in
--- fugitiveHelpTag like fugitive's own help column.
local HELP = {
  { "g?", "this help" },
  { "<Tab> / =", "toggle inline hunks" },
  { "<CR>", "open full review at file / line" },
  { "]f / [f", "next / prev file" },
  { "]c / [c", "next / prev commit" },
  { "<leader>m", "cumulative <-> incremental" },
  { "<leader>gC", "pick commit" },
  { "<leader>gA", "whole PR view" },
  { "R", "re-render" },
  { "q", "back" },
}

local function help()
  local keyw, width = 0, 0
  for _, h in ipairs(HELP) do
    keyw = math.max(keyw, #h[1])
  end
  local lines = {}
  for _, h in ipairs(HELP) do
    lines[#lines + 1] = (" %-" .. keyw .. "s  %s"):format(h[1], h[2])
    width = math.max(width, #lines[#lines])
  end
  local b = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
  vim.bo[b].modifiable = false
  vim.bo[b].bufhidden = "wipe"
  for i, h in ipairs(HELP) do
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
    title = " pr ",
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

---@param dir 1|-1
local function file_step(dir)
  local cur = vim.fn.line "."
  local best
  for _, row in pairs(file_rows) do
    if dir == 1 and row > cur and (not best or row < best) then best = row end
    if dir == -1 and row < cur and (not best or row > best) then best = row end
  end
  if best then vim.api.nvim_win_set_cursor(0, { best, 0 }) end
end

-- ------------------------------------------------------------------ open ---

local function ensure_buf()
  if buf and vim.api.nvim_buf_is_valid(buf) then return end
  buf = vim.api.nvim_create_buf(false, true)
  attached = false
  vim.api.nvim_buf_set_name(buf, "pr://files")
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "prfiles"

  local o = { buffer = buf, silent = true }
  vim.keymap.set("n", "<Tab>", toggle, o)
  vim.keymap.set("n", "=", toggle, o)
  vim.keymap.set("n", "<CR>", dive, o)
  vim.keymap.set("n", "]f", function() file_step(1) end, o)
  vim.keymap.set("n", "[f", function() file_step(-1) end, o)
  vim.keymap.set("n", "R", function() M.render() end, o)
  vim.keymap.set("n", "g?", help, o)
  vim.keymap.set("n", "q", "<cmd>silent! buffer #<cr>", o)
end

function M.open()
  ensure_buf()
  local was_active = M.active()
  if not was_active then vim.api.nvim_win_set_buf(0, buf) end
  vim.api.nvim_set_option_value("wrap", false, { win = 0, scope = "local" })
  M.render()
  if not was_active then
    -- Land on the first file row, wherever the header ends.
    local first = math.huge
    for _, row in pairs(file_rows) do
      first = math.min(first, row)
    end
    if first == math.huge then first = vim.api.nvim_buf_line_count(buf) end
    vim.api.nvim_win_set_cursor(0, { math.min(first, vim.api.nvim_buf_line_count(buf)), 0 })
  end
end

return M
