-- pr.verbs: the write side of the flow - the things that CHANGE a PR.
--
--   D  draft <-> ready     M  merge (escalates to auto-merge on refusal)
--   O  open in browser     C  check out the branch
--   X  close
--
-- Capitals on purpose: every one of these letters is a no-op in a
-- non-modifiable buffer (D/C are line operators, O/X/A insert-or-delete),
-- so nothing useful is shadowed - and the review keys stay lowercase.
--
-- One verb works on BOTH surfaces. pr://list acts on the cursor line,
-- pr://files on the loaded PR, and since both hand back the SAME PR table
-- (pr.list.order entries are what pr.load stores in state.pr), a verb that
-- flips pr.isDraft is seen by every surface at once - no re-fetch to show
-- the new state.
--
-- Prompts are vim.fn.confirm, deliberately: it is the one picker that draws
-- in the cmdline at the bottom of the screen, right under the error that
-- provoked it. fzf and vim.ui.select float away over the diff.

local data = require "pr.data"

local M = {}

local function warn(msg) vim.notify("pr: " .. msg, vim.log.levels.WARN) end
local function info(msg) vim.notify("pr: " .. msg, vim.log.levels.INFO) end

--- The PR a verb acts on, plus its repo root.
---@return string? root, table? pr
local function target()
  local list = package.loaded["pr.list"]
  if list and vim.api.nvim_buf_get_name(0):match "pr://list$" then
    local p = list.order[vim.fn.line "."]
    if p and list.root then return list.root, p end
  end
  local s = require("pr").state
  if s.pr and s.root then return s.root, s.pr end
end

--- Re-paint whatever surfaces are live, without touching the network. Used
--- after a verb mutates the PR table in place.
local function repaint()
  local list = package.loaded["pr.list"]
  if list then list.repaint() end
  local view = package.loaded["pr.view"]
  if view and view.active() then view.render() end
end

--- The PR is decided - merged, closed, or handed to the forge to merge when
--- its checks pass. Either its row is gone or the stack shape around it
--- moved, and only origin knows which, so this is a real re-fetch. From
--- either PR surface that means landing back on the list - the diff below
--- is of something that no longer needs reviewing.
local function settled()
  local name = vim.api.nvim_buf_get_name(0)
  if name:match "pr://" then return require("pr.list").open(true) end
  require("pr.list").invalidate() -- :PR merge from elsewhere: refetch on next open
end

---@return boolean
local function yes(msg) return vim.fn.confirm(msg, "&yes\n&no", 2) == 1 end

-- ------------------------------------------------------------------ draft ---

--- One key, both directions - the current state decides which. No confirm:
--- the same key undoes it.
function M.draft()
  local root, p = target()
  if not p then return warn "no PR here" end
  local to = not p.isDraft
  info(("#%d -> %s..."):format(p.number, to and "draft" or "ready"))
  data.set_draft(root, p, to, function(ok, err)
    if not ok then return warn((to and "draft" or "ready") .. " failed: " .. (err or "")) end
    p.isDraft = to
    info(("#%d is %s"):format(p.number, to and "draft" or "ready"))
    repaint()
  end)
end

-- ------------------------------------------------------------------ merge ---

local STYLES = { "squash", "merge", "rebase" }

--- Ask only what the repo actually allows (pr.data.merge_policy):
---   nothing known -> plain y/n, forge picks the style (tea)
---   one style     -> y/n, naming it
---   several       -> s/m/r, pre-selecting the forge's own default
--- confirm returns 0 on <Esc> and #allowed+1 on "quit", both of which index
--- past the list and abort.
---@return string? style  "" = let the forge decide; nil = cancelled
local function choose_style(p, policy)
  local allowed = policy.allowed
  if #allowed == 0 then return yes(("merge #%d?"):format(p.number)) and "" or nil end
  if #allowed == 1 then return yes(("merge #%d (%s)?"):format(p.number, allowed[1])) and allowed[1] or nil end
  local labels, default = {}, 1
  for i, s in ipairs(allowed) do
    labels[i] = "&" .. s
    if s == policy.default then default = i end
  end
  labels[#labels + 1] = "&quit"
  return allowed[vim.fn.confirm(("merge #%d?"):format(p.number), table.concat(labels, "\n"), default)]
end

--- What to offer after a refusal. There are two ways out and the refusal
--- text rarely says which one it wants, so they share one menu:
---   auto-merge  - the merge was refused because the CHECKS are not done.
---                 Hand it back to the forge to merge when they are. This
---                 is the escalation, and it is the default: it waits for
---                 branch protection rather than overriding it.
---   a different style - the repo does not allow the one we tried. Offered
---                 on tea only; merge_policy already narrowed gh's menu to
---                 styles the repo permits, so a style retry there would
---                 just fail the same way.
---@param tried string the style that was just refused
---@return "auto"|string? choice  a style name = retry with it; nil = give up
local function choose_retry(root, msg, tried)
  local labels, choices = { "&auto-merge when checks pass" }, { "auto" }
  if data.forge(root) ~= "gh" then
    for _, s in ipairs(STYLES) do
      if s ~= tried then
        labels[#labels + 1] = "&" .. s
        choices[#choices + 1] = s
      end
    end
  end
  labels[#labels + 1] = "&quit"
  return choices[vim.fn.confirm(msg .. "escalate?", table.concat(labels, "\n"), 1)]
end

local function do_merge(root, p, style, auto)
  info(("%s #%d..."):format(auto and "scheduling auto-merge on" or "merging", p.number))
  data.merge(root, p, { style = style ~= "" and style or nil, auto = auto }, function(ok, err)
    if ok then
      -- Both forges merge on the spot when the PR is already mergeable, so
      -- an auto-merge that succeeded may mean "merged", not "queued". The
      -- re-fetch below is what actually resolves which.
      info(("#%d %s"):format(p.number, auto and "merges once its checks pass" or "merged"))
      return settled()
    end
    -- The escalation prompt carries the refusal with it, so the reason and
    -- the menu sit in the cmdline together.
    local msg = ("%s #%d failed:\n%s\n\n"):format(auto and "auto-merge" or "merge", p.number, err or "?")
    if auto then return warn(msg) end -- already escalated: nothing left to offer
    local choice = choose_retry(root, msg, style)
    if choice == "auto" then return do_merge(root, p, style, true) end
    if choice then do_merge(root, p, choice, false) end
  end)
end

function M.merge()
  local root, p = target()
  if not p then return warn "no PR here" end
  if p.isDraft and not yes(("#%d is a draft. merge anyway?"):format(p.number)) then return end
  data.merge_policy(root, function(policy)
    local style = choose_style(p, policy)
    if style then do_merge(root, p, style, false) end
  end)
end

-- ------------------------------------------------------- close / checkout ---

function M.close()
  local root, p = target()
  if not p then return warn "no PR here" end
  if not yes(("close #%d without merging?"):format(p.number)) then return end
  data.close(root, p, function(ok, err)
    if not ok then return warn("close failed: " .. (err or "")) end
    info(("#%d closed"):format(p.number))
    settled()
  end)
end

--- Check out the PR branch into the working tree. Fires FugitiveChanged so
--- the statusline / fugitive buffers notice the branch moved under them.
function M.checkout()
  local root, p = target()
  if not p then return warn "no PR here" end
  info(("checking out #%d..."):format(p.number))
  data.checkout(root, p, function(ok, err)
    if not ok then return warn("checkout failed: " .. (err or "")) end
    info(("#%d checked out%s"):format(p.number, p.headRefName and (" (" .. p.headRefName .. ")") or ""))
    pcall(vim.cmd, "silent! doautocmd User FugitiveChanged")
  end)
end

function M.web()
  local root, p = target()
  if not p then return warn "no PR here" end
  local url = data.web_url(root, p.number)
  if not url then return warn "could not derive a URL from origin" end
  local ok, err = pcall(vim.ui.open, url)
  if not ok then return warn("open failed: " .. tostring(err)) end
  info(url)
end

-- ------------------------------------------------------------------- maps ---

--- The verb keys, shared verbatim by pr://list and pr://files so a verb is
--- the same keystroke wherever you are.
M.KEYS = {
  { "D", "draft", "draft <-> ready" },
  { "M", "merge", "merge (auto-merge on refusal)" },
  { "C", "checkout", "check out the branch" },
  { "O", "web", "open in browser" },
  { "X", "close", "close without merging" },
}

---@param buf integer
function M.attach(buf)
  for _, k in ipairs(M.KEYS) do
    vim.keymap.set("n", k[1], function() M[k[2]]() end, { buffer = buf, silent = true, desc = "pr: " .. k[3] })
  end
end

--- The verb rows for a g? help float.
---@return {[1]:string,[2]:string}[]
function M.help_entries()
  local out = {}
  for _, k in ipairs(M.KEYS) do
    out[#out + 1] = { k[1], k[3] }
  end
  return out
end

return M
