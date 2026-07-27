-- pr: move between PRs, and between commits inside a PR.
--
--   <leader>gP   pick a PR (fzf)      ]c / [c     next / prev commit
--   <leader>gf   files view           <leader>gm  cumulative <-> incremental
--   <leader>gC   pick a commit        <leader>gA  whole-PR view
--
-- The files view (pr.view) is the single surface: picking a PR lands there,
-- and every navigation re-renders it. The full diffs.nvim review is reached
-- only by <CR> on a file row inside the view.
--
-- State is five values. Every action recomputes a range and re-renders.

local data = require "pr.data"

local M = {}

---@class pr.State
local S = {
  root = nil, ---@type string?
  pr = nil, ---@type table?
  base = nil, ---@type string?
  target = nil, ---@type string?
  commits = {}, ---@type table[]
  idx = 0,
  mode = "cumulative", ---@type "cumulative"|"incremental"
}

M.state = S

local function warn(msg) vim.notify("pr: " .. msg, vim.log.levels.WARN) end
local function info(msg) vim.notify("pr: " .. msg, vim.log.levels.INFO) end

--- Load fzf-lua THROUGH lz.n so its `after` hook (fzf.setup with fullscreen,
--- borders, ...) runs; a raw packadd skips setup and yields stock winopts.
local function fzf()
  local ok_lz, lzn = pcall(require, "lz.n")
  if ok_lz then pcall(lzn.trigger_load, "fzf-lua") end
  pcall(vim.cmd.packadd, "fzf-lua")
  local ok, mod = pcall(require, "fzf-lua")
  return ok and mod or nil
end

--- Open (or re-render) the files view. The one and only render entry point.
function M.render()
  if #S.commits == 0 then return warn "no PR loaded - <leader>gP first" end
  require("pr.view").open()
end

M.files = M.render

-- --------------------------------------------------------------- loading ---

local function load_pr(root, pr)
  local ref = data.ref(pr.number)

  local function go()
    S.root, S.pr = root, pr
    S.base = "origin/" .. pr.baseRefName
    S.target = ref
    S.commits = data.commits(root, S.base, ref)
    if #S.commits == 0 then return warn("no commits in #" .. pr.number) end
    S.idx = #S.commits -- tip: cumulative at the tip == the whole PR
    S.mode = "cumulative"
    M.render()
  end

  if data.ref_exists(root, ref) then return go() end

  info("fetching #" .. pr.number .. "...")
  data.fetch(root, function(ok, err)
    if not ok then return warn("fetch failed: " .. (err or "")) end
    if not data.ref_exists(root, ref) then
      return warn("no local ref " .. ref .. " - is the pull refspec installed? :PR refspec")
    end
    go()
  end)
end

-- --------------------------------------------------------------- pickers ---

--- "3d ago" from an ISO-8601 timestamp; both sides shifted equally through
--- os.time, so the local-tz interpretation cancels out.
local function ago(iso)
  local y, mo, d, h, mi, sec = (iso or ""):match "(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)"
  if not y then return "" end
  local t = os.time { year = y, month = mo, day = d, hour = h, min = mi, sec = sec }
  local dt = os.time(os.date "!*t") - t
  if dt < 3600 then return math.max(1, math.floor(dt / 60)) .. "m" end
  if dt < 86400 then return math.floor(dt / 3600) .. "h" end
  if dt < 86400 * 30 then return math.floor(dt / 86400) .. "d" end
  return math.floor(dt / 86400 / 30) .. "mo"
end

function M.pick_pr()
  local root = data.root()
  if not root then return warn "not in a git repository" end

  -- Self-serve: install the pull refspec on first use instead of nagging.
  if not data.has_refspec(root) then
    if not data.install_refspec(root) then return warn "could not write git config" end
    info "installed pull refspec for this repo"
  end

  local f = fzf()
  if not f then return warn "fzf-lua not available" end

  info "loading PRs..."
  data.prs(root, function(prs, err)
    if not prs then return warn(err or "could not list PRs") end
    if #prs == 0 then return info "no open PRs" end

    -- Fixed columns: number | title | [draft] | author | age. Truncation and
    -- padding go by DISPLAY width, not bytes - "…" is 3 bytes but 1 cell, and
    -- byte-based %-Ns padding scatters every column after a multibyte char.
    local function fit(str, w)
      if vim.fn.strdisplaywidth(str) > w then
        while vim.fn.strdisplaywidth(str) > w - 1 do
          str = vim.fn.strcharpart(str, 0, vim.fn.strchars(str) - 1)
        end
        str = str .. "…"
      end
      return str .. string.rep(" ", w - vim.fn.strdisplaywidth(str))
    end

    local A = require("fzf-lua.utils").ansi_codes
    local entries, by = {}, {}
    for _, p in ipairs(prs) do
      -- Draft is carried by the grey number alone - no [draft] column.
      local num = ("#%-5d"):format(p.number)
      local author = fit(p.author and p.author.login or "?", 14)
      entries[#entries + 1] = table.concat {
        p.isDraft and A.grey(num) or A.green(num),
        " ",
        fit(p.title or "", 58),
        " ",
        A.magenta(author),
        " ",
        A.grey(("%4s"):format(ago(p.updatedAt))),
      }
      by[p.number] = p
    end

    f.fzf_exec(entries, {
      prompt = "PR> ",
      winopts = { fullscreen = true },
      fzf_opts = { ["--ansi"] = true, ["--no-multi"] = true },
      actions = {
        -- fzf strips ANSI from selections: key on the PR number, not the line.
        ["default"] = function(sel)
          local n = sel and sel[1] and tonumber(sel[1]:match "^#(%d+)")
          local p = n and by[n]
          if p then load_pr(root, p) end
        end,
      },
    })
  end)
end

function M.pick_commit()
  if #S.commits == 0 then return warn "no PR loaded - <leader>gP first" end
  local f = fzf()
  if not f then return warn "fzf-lua not available" end

  -- git-log semantics: sha yellow, author blue, age grey.
  local A = require("fzf-lua.utils").ansi_codes
  local entries, by = {}, {}
  for i, c in ipairs(S.commits) do
    entries[#entries + 1] = table.concat({
      A.yellow(c.sha),
      c.subject,
      A.blue("<" .. c.author .. ">"),
      A.grey("(" .. c.ago .. ")"),
    }, "  ")
    by[c.sha] = i
  end

  -- Preview mirrors whichever mode you are in, so what you see is what loads.
  local root = vim.fn.shellescape(S.root)
  local preview = S.mode == "incremental"
      and ("git -C %s show --color {1}"):format(root)
    or ("git -C %s diff --color %s...{1}"):format(root, vim.fn.shellescape(S.base))

  f.fzf_exec(entries, {
    prompt = ("commit [%s]> "):format(S.mode),
    winopts = { fullscreen = true },
    fzf_opts = { ["--ansi"] = true, ["--preview"] = preview, ["--preview-window"] = "right:60%" },
    actions = {
      -- fzf strips ANSI from selections: key on the sha, not the line.
      ["default"] = function(sel)
        local i = sel and sel[1] and by[sel[1]:match "^(%x+)"]
        if i then
          S.idx = i
          M.render()
        end
      end,
    },
  })
end

-- ------------------------------------------------------------- navigation ---

---@param delta integer
function M.step(delta)
  if #S.commits == 0 then return warn "no PR loaded - <leader>gP first" end
  local n = #S.commits
  S.idx = ((S.idx - 1 + delta) % n) + 1
  M.render()
end

function M.toggle_mode()
  if #S.commits == 0 then return warn "no PR loaded - <leader>gP first" end
  S.mode = S.mode == "cumulative" and "incremental" or "cumulative"
  M.render()
end

--- Jump back to the whole-PR view (cumulative at the tip).
function M.whole()
  if #S.commits == 0 then return warn "no PR loaded - <leader>gP first" end
  S.idx, S.mode = #S.commits, "cumulative"
  M.render()
end

-- ------------------------------------------------------------------ setup ---

function M.refspec()
  local root = data.root()
  if not root then return warn "not in a git repository" end
  if data.has_refspec(root) then return info "pull refspec already installed" end
  if not data.install_refspec(root) then return warn "could not write git config" end
  info "refspec installed, fetching PR refs..."
  data.fetch(root, function(ok, err)
    if ok then
      info "PR refs available - <leader>gP to pick one"
    else
      warn("fetch failed: " .. (err or ""))
    end
  end)
end

return M
