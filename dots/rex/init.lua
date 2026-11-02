local terminal = "com.superlogical.terminal"

local function call(server, method, args)
  local result, err = server.call(method, args)
  if not result then error(err, 0) end
  return result
end

local function this_host()
  return rex.exec{ "uname", "-s" }.stdout:match("Darwin") and "macbook" or "spark"
end

local function open_host(ctx, host)
  if host == this_host() then return end
  local name = rex.servers()[1]
  if not name then error("not connected to " .. host, 0) end
  local server = rex.server(name)
  local sessions = call(server, "session.list").sessions or {}
  local id = sessions[1] and sessions[1].session_id
    or call(server, "session.create", {
      initial_windows = { { layout = rex.layout.block{ flavor = terminal .. ".shell" } } },
    }).session_id
  local switched
  for _, client in ipairs(call(server, "client.list").clients or {}) do
    if client.info.kind == "app" and client.connection_state ~= "lost" then
      switched = server.call("client.perform", {
        client_id = client.client_id,
        action = "session.select",
        args = { session_id = id },
      }) or switched
    end
  end
  if not switched then error("no Rex app connected to " .. host, 0) end
end

for key, host in pairs({ ["1"] = "macbook", ["2"] = "spark" }) do
  rex.action{
    name = "open_" .. host,
    title = "Open " .. host,
    category = "Session",
    run = function(ctx) open_host(ctx, host) end,
  }
  rex.bind("cmd+shift+" .. key, "open_" .. host)
end

rex.action{
  name = "clear_screen",
  title = "Clear Screen",
  category = "Terminal",
  run = function() rex.block.call(terminal, "clear", {}) end,
}
rex.bind("cmd+k", "clear_screen")

local placements = {
  left = { direction = "horizontal", side = "before" },
  down = { direction = "vertical", side = "after" },
  up = { direction = "vertical", side = "before" },
  right = { direction = "horizontal", side = "after" },
}

local function blocks(node, out)
  if node.block_id then
    local r = node.rect
    out[#out + 1] = { id = node.block_id, x = r[1] + r[3] / 2, y = r[2] + r[4] / 2 }
  elseif node.split then
    blocks(node.split.before, out)
    blocks(node.split.after, out)
  end
  return out
end

local function nearest(ctx, direction)
  for _, window in ipairs((rex.session.view{} or {}).windows or {}) do
    for _, layer in ipairs(window.layers or {}) do
      local found = layer.layout and blocks(layer.layout, {}) or {}
      local me
      for _, b in ipairs(found) do
        if b.id == ctx.block_id then me = b end
      end
      if me then
        local best, best_score
        for _, b in ipairs(found) do
          if b.id ~= me.id then
            local dx, dy = b.x - me.x, b.y - me.y
            local ahead = (direction == "left" and dx < 0) or (direction == "right" and dx > 0)
              or (direction == "up" and dy < 0) or (direction == "down" and dy > 0)
            local score = dx * dx + dy * dy + (ahead and 0 or 1e9)
            if not best or score < best_score then best, best_score = b.id, score end
          end
        end
        return best
      end
    end
  end
end

for direction, placement in pairs(placements) do
  rex.action{
    name = "move_pane_" .. direction,
    title = "Move Pane " .. direction:sub(1, 1):upper() .. direction:sub(2),
    category = "Layout",
    run = function(ctx)
      local anchor = nearest(ctx, direction)
      if not anchor then return end
      local _, err = rex.session.move_block{
        block_id = ctx.block_id,
        anchor_block_id = anchor,
        direction = placement.direction,
        side = placement.side,
      }
      if err then error(err, 0) end
    end,
  }
end

rex.bind("cmd+alt+left", "pane.focus.left")
rex.bind("cmd+alt+down", "pane.focus.down")
rex.bind("cmd+alt+up", "pane.focus.up")
rex.bind("cmd+alt+right", "pane.focus.right")
rex.bind("cmd+[", "pane.focus_previous")
rex.bind("cmd+]", "pane.focus_next")

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
rex.bind("ctrl+b>s", "session.switch")
rex.bind("ctrl+b>shift+c", "session.new")
rex.bind("ctrl+b>shift+4", "session.rename")
rex.bind("ctrl+b>shift+x", "session.close")
rex.bind("ctrl+b>shift+h", "client.host.switch")
rex.bind("ctrl+b>c", "client.tab.new")
rex.bind("ctrl+b>n", "client.tab.next")
rex.bind("ctrl+b>p", "client.tab.previous")
for i = 1, 9 do
  rex.bind("ctrl+b>" .. i, "client.tab.goto", { index = i })
end

rex.bind("ctrl+b>r", "client.mode.enter", { name = "resize" })
rex.bind("resize/h", "pane.resize", { direction = "left" })
rex.bind("resize/j", "pane.resize", { direction = "down" })
rex.bind("resize/k", "pane.resize", { direction = "up" })
rex.bind("resize/l", "pane.resize", { direction = "right" })
rex.bind("resize/shift+h", "move_pane_left")
rex.bind("resize/shift+j", "move_pane_down")
rex.bind("resize/shift+k", "move_pane_up")
rex.bind("resize/shift+l", "move_pane_right")
rex.bind("resize/enter", "client.mode.exit")
rex.bind("resize/q", "client.mode.exit")
