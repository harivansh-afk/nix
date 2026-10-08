-- Rex reads this on the Mac's Rex server: ~/.config/rex/init.lua links here.
-- Apply edits with `rex config reload`; `rex keymap` shows the merged result.

local terminal = "com.superlogical.terminal"
local shells = { zsh = true, bash = true, fish = true, sh = true }

-- Ghostty's clear_screen: drop the screen and scrollback, then let an idle
-- shell redraw its prompt. A full-screen program is left alone.
rex.action{
  name = "clear_screen",
  title = "Clear Screen",
  category = "Terminal",
  run = function(ctx)
    local process = rex.block.call(terminal, "process", { block_id = ctx.block_id })
    local foreground = process and process.foreground and process.foreground.name
    if foreground and not shells[foreground] then
      return
    end
    rex.block.call(terminal, "clear", { block_id = ctx.block_id })
    rex.block.call(terminal, "write", { block_id = ctx.block_id, data = "\f" })
  end,
}
rex.bind("cmd+k", "clear_screen")

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
rex.bind("resize/escape", "client.mode.exit")
rex.bind("resize/enter", "client.mode.exit")
rex.bind("resize/q", "client.mode.exit")
