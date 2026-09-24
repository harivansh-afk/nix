# Spark browser and desktop

Use pinned **agent-browser 0.36.0 CLI** for browser work and **Cua Driver
0.28.3-nightly.20260924.35955966930 MCP** for native apps. The driver and its
skills use the same immutable nightly, built from upstream commit
`6762bcf63b616c6de86ab7b2309686150913105b`. There is no Playwright MCP or custom Python execution
server. Nix installs the upstream binaries and version-matched skills; no runtime
npm/uvx installs are needed. The [shared skill](../../../dots/agents/skills/spark-computer/SKILL.md)
contains the agent workflow.

## Browser lifecycle

Sway starts Cua, WayVNC and Beeper, not Chromium. Chromium retains its existing
profile/keyring and loopback CDP port 19222. `Restart=on-failure` respects normal
window closure. An agent starts it explicitly only when a browser task needs it:

```sh
systemctl --user start chromium
curl --retry 20 --retry-connrefused --retry-delay 1 --max-time 2 --fail --silent http://127.0.0.1:19222/json/version
/run/current-system/sw/bin/agent-browser --session unique-task --cdp 19222 --pin-tab open https://example.com
/run/current-system/sw/bin/agent-browser --session unique-task --cdp 19222 --pin-tab snapshot -i
```

Use unique sessions and strict tab pinning. Never navigate someone else's tab,
copy profiles, export cookies, or expose CDP publicly. Close only the task tab,
then its CLI session. Stop Chromium afterward only if the task started it and
nobody else needs it. Explicit task startup is intentional, not a hidden daemon
that resurrects the browser during tool discovery.

Use the absolute system binary: background/login shells can resolve an older
user-installed agent-browser without `--pin-tab`.

## Window controls

Waybar shows the focused window's title and a top-right **Close ×** button.
It requests a normal close of that window, not a process kill. **Alt+F4** and
**Super+Shift+Q** do the same. Sway does not provide per-window X buttons.
Beeper's service must remain running for messaging; closing its window is not
the way to stop its API. After deploying into an existing Sway session, start
the new bar with `systemctl --user start waybar` if needed.

## Native apps

`spark-cua-mcp` only resolves the user runtime directory and executes upstream
`cua-driver mcp --socket .../cua-driver/control.sock`. The existing user service
owns the Sway and D-Bus environment. Hermes, Codex, Claude Code and omp connect
to this same native backend. The facade's `computer_exec`/`computer_close` tools
are removed; start fresh agent sessions after deployment.

GTK uses `GTK_A11Y=atspi` to expose native controls. Use exact PID/window IDs and
fresh element tokens. Coordinate native tasks: MCP clients do not have independent
input seats. Stock Sway cannot deliver arbitrary background raw input into an
occluded window; foreground escalation needs explicit authorization.

```sh
systemctl --user status sway chromium cua-driver wayvnc --no-pager
cua-driver call list_windows '{}' --socket "/run/user/$(id -u)/cua-driver/control.sock"
```
