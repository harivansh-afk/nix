local terminal = "com.superlogical.terminal"

local hosts = {
  macbook = "01fe5070-9629-4724-8a6e-bc2069dee2c5",
  spark = "b6c8a0f1-5153-4e4d-a7e8-a4bad784d379",
}

local function call(server, method, args)
  local result, err = server.call(method, args)
  if not result then error(err, 0) end
  return result
end

local function server_for(host)
  if call(rex, "server.status").host_id == hosts[host] then return rex end
  local names = rex.servers()
  for _, name in ipairs(names) do
    local server = rex.server(name)
    if call(server, "server.status").host_id == hosts[host] then return server end
  end
  error("not connected to " .. host .. " (servers: " .. table.concat(names, ", ") .. ")", 0)
end

local function open_host(ctx, host)
  local server = server_for(host)
  local sessions = call(server, "session.list").sessions or {}
  for _, session in ipairs(sessions) do
    if session.session_id == ctx.session_id then return end
  end
  local id = sessions[1] and sessions[1].session_id
    or call(server, "session.create", {
      initial_windows = { { layout = rex.layout.block{ flavor = terminal .. ".shell" } } },
    }).session_id
  local me = call(rex, "client.inspect", { client_id = ctx.client_id }).client.info
  for _, client in ipairs(call(server, "client.list").clients or {}) do
    if client.info and client.info.kind == "app" and client.info.label == me.label then
      call(server, "client.perform", {
        client_id = client.client_id,
        action = "session.select",
        args = { session_id = id },
      })
    end
  end
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
rex.bind("resize/shift+h", "pane.move.left")
rex.bind("resize/shift+j", "pane.move.down")
rex.bind("resize/shift+k", "pane.move.up")
rex.bind("resize/shift+l", "pane.move.right")
rex.bind("resize/enter", "client.mode.exit")
rex.bind("resize/q", "client.mode.exit")
