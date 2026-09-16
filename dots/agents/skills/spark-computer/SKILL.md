---
name: spark-computer
description: Use Spark's agent-browser CLI and native Cua MCP.
---

# Spark computer

Use **agent-browser CLI** for websites and upstream **Cua Driver MCP** (`computer`)
for native apps. No custom Python execution server or browser MCP.

## Browser

Load the version-matched guide with `agent-browser skills get core`.
Start Chromium only for a requested browser task:

```sh
systemctl --user start chromium
curl --retry 20 --retry-connrefused --retry-delay 1 --max-time 2 --fail --silent http://127.0.0.1:19222/json/version
agent-browser --session <unique-task> --cdp 19222 --pin-tab open <url>
agent-browser --session <unique-task> --cdp 19222 --pin-tab snapshot -i
```

Use a unique session and `--pin-tab` on shared CDP. These create a task-owned
page instead of navigating an existing user tab. Use observed refs to click/fill;
refresh snapshots after page changes. Batch known actions with `&&` or upstream
`batch --bail`, then verify the result. Use screenshots for visual checks; load
local image paths with `vision_analyze` in Hermes.

Close only the task's pinned tab with `tab close`, then `close` its CLI session.
Never use `close --all`. A closed pinned tab must produce an error, not silently
switch to someone else's tab. Do not retry mutations blindly after transport loss.
Cookies and account state remain shared: coordinate work on the same account.
Do not export cookies, copy profiles, or launch a second browser on this profile.
CDP stays loopback-only.

Chromium does not start at desktop login and normal window closure stays closed.
If you started it and no other task/user needs it, stop it with
`systemctl --user stop chromium`. Never stop a pre-existing shared browser.

## Native apps

Load `cua-driver` and its `LINUX.md`. The `computer` MCP connects directly to
`cua-driver mcp --socket "$XDG_RUNTIME_DIR/cua-driver/control.sock"`.
Discover exact schemas before unfamiliar calls.

1. `list_windows`: select the observed PID and window ID.
2. `get_window_state`: inspect that exact window; prefer fresh `element_token`s.
3. Use upstream actions, then verify through fresh state, pixels, or application
   output. `unknown` and `unverifiable` do not mean success.
4. End named sessions after use. Serialize native interactions and yield to the
   user: separate MCP clients are not separate input seats.

Stock Sway cannot inject arbitrary background input into occluded windows.
Foreground escalation needs explicit authorization. Never bypass a refusal.
GTK field text may be absent from accessibility output; verify visually or through
application output instead of trusting an action response alone.

Diagnostics: `hosts/spark/docs/browser.md` in the Nix repo.
