# Spark browser and desktop automation

Run browser and CUA commands on Spark as Hari, including when working from the
Mac over SSH. The desktop is Sway on Wayland, visible through VNC. Tools share
Hari's desktop and original Chromium profile: coordinate actions, preserve
existing tabs and yield when Hari takes over.

## Browser pages

For an existing-browser task, attach explicitly to the Nix-owned loopback CDP
endpoint. Check it before operating:

```sh
curl --fail --silent --show-error http://127.0.0.1:19222/json/version
agent-browser --cdp 19222 tab
agent-browser --cdp 19222 snapshot -i
```

Select the intended tab from the listing before acting. Use the fresh snapshot's
element references with `click`, `fill` and other commands; take another snapshot
after navigation or page changes, then verify the requested result. Consult
`agent-browser --help` for the installed command syntax. Prefer a new task tab
when the request does not concern an existing tab; close only tabs you created.
Leave the browser running when finished.

CDP is the browser connection; agent-browser is the CLI using that connection.
Always pass `--cdp 19222` for this workflow. A plain invocation can launch a
separate browser, and auto-discovery can select another debugging endpoint.
Separate CLI session names do not isolate tabs or input in the attached browser.

If the endpoint fails, inspect the Chromium process and Sway service and report
the failure. Fix launch configuration in `hosts/spark/services/desktop.nix`;
an already-running browser needs a restart to pick up changed flags. Keep
`~/.config/chromium` as private mutable state. Remote debugging is loopback-only;
an off-host CDP client needs an SSH tunnel.

## Native desktop and browser UI

Use `cua-driver` for native apps, browser chrome, dialogs and GUI interactions
that page automation cannot handle. Read `~/.agents/skills/cua-driver/SKILL.md`
and its `LINUX.md` companion first; Hermes has the same versioned skill under
its own skills directory. Follow its snapshot, action and verification loop.

An SSH or agent shell may lack the desktop environment. In the shell that will
run CUA, load the active Sway display from Hari's user manager:

```sh
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
export WAYLAND_DISPLAY="$(systemctl --user show-environment | sed -n 's/^WAYLAND_DISPLAY=//p')"
export SWAYSOCK="$(systemctl --user show-environment | sed -n 's/^SWAYSOCK=//p')"
export XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=sway
export CUA_DRIVER_RS_ENABLE_WAYLAND=1 CUA_DRIVER_RS_TELEMETRY_ENABLED=0
test -n "$WAYLAND_DISPLAY" && test -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
systemctl --user status cua-driver --no-pager
cua-driver doctor
cua-driver call list_windows '{}'
```

Sway imports the display environment and starts the Nix-owned `cua-driver` user
service. CLI calls connect to its default private Unix socket. If it is inactive
after a deployment into an existing desktop, run `systemctl --user start cua-driver`
after confirming the display environment above. Inspect its journal if startup
fails; Hermes manages its own native computer-use runtime separately.

Proceed when the display socket exists and `list_windows` finds the intended
window. The pinned driver's doctor includes X11-oriented warnings on native
Wayland, so use actual window discovery and a fresh window snapshot to verify
capabilities. Discover operations with `cua-driver list-tools` and inspect their
arguments with `cua-driver describe <tool>` before `cua-driver call`. Verify each
action from fresh state. On Wayland, background accessibility support varies by
application; foreground mouse/keyboard actions share focus with Hari and other
agents. A successful command alone does not prove the UI changed.

Hermes keeps its native `browser_exec` profile-snapshot workflow for independent
browser sessions. When asked to operate the original visible browser, use the
CDP workflow above; its native `computer_use` tool handles desktop tasks.
