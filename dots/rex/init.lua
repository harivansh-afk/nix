-- Rex reads this on the Mac's Rex server: ~/.config/rex/init.lua links here.
-- Apply edits with `rex config reload`; `rex keymap` shows the merged result.

local terminal = "com.superlogical.terminal"
local shells = { zsh = true, bash = true, fish = true, sh = true }

-- Ghostty's clear_screen: drop the screen and scrollback, then let an idle
-- shell redraw its prompt. A full-screen program is left alone. The program
-- is what the foreground was invoked as: a spark pane's relay presents
-- itself as the program in its pty's foreground (`zsh` at the prompt, so it
-- clears; `claude` while claude runs, so it is left alone). A mosh relay
-- gets the form feed too: the shell behind it redraws, a full-screen
-- program there just repaints.
local relays = { ["mux-attach"] = true, ["mosh-client"] = true }
local function basename(path)
  return path and path:match("([^/]+)$")
end
rex.action{
  name = "clear_screen",
  title = "Clear Screen",
  category = "Terminal",
  run = function(ctx)
    local process = rex.block.call(terminal, "process", { block_id = ctx.block_id })
    local foreground = process and process.foreground
    local program = foreground
      and (basename(foreground.argv0) or basename(foreground.invoked_path) or foreground.name)
    if program and not shells[program] and not relays[program] then
      return
    end
    rex.block.call(terminal, "clear", { block_id = ctx.block_id })
    rex.block.call(terminal, "write", { block_id = ctx.block_id, data = "\f" })
  end,
}
rex.bind("cmd+k", "clear_screen")

-- Every pane attaches to spark through rex-spark (dots/zsh/zshrc). These
-- split a plain Mac shell off the focused pane instead, through the CLI:
-- `rex run` starts the command from a non-interactive login shell, so zshrc
-- never routes it to spark, and REX_LOCAL marks it for the prompt.
-- The new shell starts in the anchor pane's directory, from its OSC 7
-- report (`kitty-shell-cwd://host/path`; a spark pane's home maps to the
-- Mac's). Rex falls back to the home directory when that path is missing.
local rex_cli = os.getenv("HOME") .. "/.local/bin/rex"
local home = os.getenv("HOME")
local directions = { h = "left", j = "below", k = "above", l = "right" }

local function pane_dir(ctx)
  local result = rex.block.call(terminal, "pwd", { block_id = ctx.block_id })
  local path = result and result.pwd and result.pwd:match("^[%w+.-]+://[^/]*(/.*)$")
  if not path then return home end
  path = path:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
  return (path:gsub("^/home/[^/]+", home))
end

for key, direction in pairs(directions) do
  rex.action{
    name = "local_split_" .. direction,
    title = "Local Shell " .. direction:sub(1, 1):upper() .. direction:sub(2),
    category = "Terminal",
    run = function(ctx)
      local cwd = "'" .. pane_dir(ctx):gsub("'", "'\\''") .. "'"
      os.execute(rex_cli .. " run --split=" .. direction .. " -b " .. ctx.block_id .. " --cwd " .. cwd .. " -- env REX_LOCAL=1 zsh -l")
    end,
  }
  rex.bind("ctrl+b>shift+" .. key, "local_split_" .. direction)
end

-- Move the focused pane: to that side of its neighbour in that direction,
-- or, with none there, of the nearest pane (so a stacked pair goes side by
-- side). Rects come from the session view; the CLI does the move.
local function neighbour(ctx, direction)
  local view = rex.call("session.view", { session_id = ctx.session_id or rex.session_id })
  local function blocks_with_me(window)
    for _, layer in ipairs(window and window.layers or {}) do
      for _, block in ipairs(layer.blocks or {}) do
        if block.block_id == ctx.block_id then
          return layer.blocks
        end
      end
    end
  end
  local blocks = blocks_with_me(view.focused_window)
  for _, window in ipairs(view.windows or {}) do
    if blocks then break end
    blocks = blocks_with_me(window)
  end
  if not blocks then return nil end
  local me
  for _, block in ipairs(blocks) do
    if block.block_id == ctx.block_id then me = block.rect end
  end
  local eps = 1e-6
  local best, best_distance
  for _, block in ipairs(blocks) do
    if block.block_id ~= ctx.block_id then
      local r = block.rect
      local distance
      if direction == "left" and r.x + r.w <= me.x + eps then
        distance = me.x - (r.x + r.w)
      elseif direction == "right" and r.x >= me.x + me.w - eps then
        distance = r.x - (me.x + me.w)
      elseif direction == "above" and r.y + r.h <= me.y + eps then
        distance = me.y - (r.y + r.h)
      elseif direction == "below" and r.y >= me.y + me.h - eps then
        distance = r.y - (me.y + me.h)
      end
      if distance == nil then
        local dx = (r.x + r.w / 2) - (me.x + me.w / 2)
        local dy = (r.y + r.h / 2) - (me.y + me.h / 2)
        distance = 10 + dx * dx + dy * dy
      end
      if best == nil or distance < best_distance then
        best, best_distance = block.block_id, distance
      end
    end
  end
  return best
end

for key, direction in pairs(directions) do
  rex.action{
    name = "move_pane_" .. direction,
    title = "Move Pane " .. direction:sub(1, 1):upper() .. direction:sub(2),
    category = "Layout",
    run = function(ctx)
      local anchor = neighbour(ctx, direction)
      if not anchor then return end
      os.execute(rex_cli .. " move " .. ctx.block_id .. " " .. direction .. " " .. anchor)
    end,
  }
end

-- Direct pane focus. alt+h/j/k/l belongs to AeroSpace.
rex.bind("cmd+alt+left", "pane.focus.left")
rex.bind("cmd+alt+down", "pane.focus.down")
rex.bind("cmd+alt+up", "pane.focus.up")
rex.bind("cmd+alt+right", "pane.focus.right")
rex.bind("cmd+[", "pane.focus_previous")
rex.bind("cmd+]", "pane.focus_next")

-- Mux's prefix grammar, so both multiplexers share muscle memory.
rex.bind("ctrl+b>ctrl+b", "pane.send_key", { key = "ctrl+b" })
rex.bind("ctrl+b>h", "pane.focus.left")
rex.bind("ctrl+b>j", "pane.focus.down")
rex.bind("ctrl+b>k", "pane.focus.up")
rex.bind("ctrl+b>l", "pane.focus.right")
rex.bind("ctrl+b>left", "pane.focus.left")
rex.bind("ctrl+b>down", "pane.focus.down")
rex.bind("ctrl+b>up", "pane.focus.up")
rex.bind("ctrl+b>right", "pane.focus.right")
rex.bind("ctrl+b>'", "pane.split.right")
rex.bind("ctrl+b>-", "pane.split.down")
rex.bind("ctrl+b>z", "pane.zoom")
rex.bind("ctrl+b>x", "pane.close")
rex.bind("ctrl+b>c", "client.tab.new")
rex.bind("ctrl+b>n", "client.tab.next")
rex.bind("ctrl+b>p", "client.tab.previous")
for i = 1, 9 do
  rex.bind("ctrl+b>" .. i, "client.tab.goto", { index = i })
end

rex.mode("resize")
rex.bind("ctrl+b>r", "client.mode.enter", { name = "resize" })
rex.bind("resize/h", "pane.resize", { direction = "left" })
rex.bind("resize/j", "pane.resize", { direction = "down" })
rex.bind("resize/k", "pane.resize", { direction = "up" })
rex.bind("resize/l", "pane.resize", { direction = "right" })
rex.bind("resize/shift+h", "move_pane_left")
rex.bind("resize/shift+j", "move_pane_below")
rex.bind("resize/shift+k", "move_pane_above")
rex.bind("resize/shift+l", "move_pane_right")
rex.bind("resize/escape", "client.mode.exit")
rex.bind("resize/enter", "client.mode.exit")
rex.bind("resize/q", "client.mode.exit")
