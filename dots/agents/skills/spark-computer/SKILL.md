---
name: spark-computer
description: Operate Spark's existing browser or native desktop through persistent Python, Playwright and CUA. Use for browser interaction, authenticated websites, screenshots, visual checks, dialogs and native applications on Spark.
---

# Spark computer

Use the `computer` MCP server's `computer_exec` and `computer_close` tools.
Hermes names them `mcp__computer__computer_exec` and `mcp__computer__computer_close`.
The tools run on Spark as Hari. Each task gets a unique session name; retain it
through the task, then close it. Python variables and imports persist in that
session. Different agents must choose different names.

## Browser code

Use Playwright's async API with top-level `await`. The browser helper creates
one task-owned tab in Hari's existing Chromium profile. It shares logins while
leaving existing tabs alone. Start with:

```python
page = await browser.page()
await page.goto("https://example.com")
print(await page.title())
display(await page.screenshot())
```

Use roles, labels and observed DOM state for normal controls. Group known steps
in one call and wait on specific conditions with Playwright's locators, events
and assertions. Observe again when navigation or uncertainty changes the plan.
Use `display(image_bytes_or_path)` for visual verification; it returns actual
images to the model. Inspect screenshots for canvas, layout and pixel actions.
Printing a file path alone does not display it.

`await browser.tabs()` lists existing tab metadata. To operate an existing tab
when that is explicitly the task, resolve the intended page from
`page.context.pages` using the observed URL/title and retain that reference.
Only close tabs created for this task. `computer_close` closes the helper's
owned tab and leaves the browser and other tabs running.

Session names isolate Python variables and owned tabs, not cookies or site
storage. Coordinate operations on the same account/site. Use a separate browser
context only when the task requires independent state and does not need Hari's
existing login. Close any extra context or page you create.

## Native desktop code

Set `desktop: true` on `computer_exec` when calling the desktop helper. It holds
a host-wide lock for that execution so participating agents cannot interleave
native input. Browser-only calls can run concurrently.

```python
print(await desktop.list_windows())
print(await desktop.describe("get_window_state"))
```

Select the exact window from that result. Inspect the current tool schema with
`await desktop.describe("tool_name")`, then call it as an async method:

```python
state = await desktop.get_window_state(pid=PID, window_id=WINDOW_ID)
print(state)
```

Screenshots from CUA are returned as images automatically. Use the fresh
`element_token`, or the matching `snapshot_id` and `element_index`, for semantic
actions. Re-snapshot after actions and verify the requested application state.
Use window-local screenshot coordinates for window actions; desktop images use
screen coordinates. Read the adjacent upstream `cua-driver` skill's `LINUX.md`
when a native action is refused or a compositor capability is unclear.

Prefer accessibility actions. For a task requiring visible mouse/keyboard
control, use `delivery_mode="foreground"` when needed; these actions share
Hari's visible desktop. Yield when Hari takes over. Sway cannot inject arbitrary
raw input into an obscured window independently of focus.

## Execution and recovery

The namespace includes `browser`, `desktop`, `display`, `asyncio` and normal
Python builtins. Use async APIs; timeouts are cooperative and cannot interrupt
blocking Python. Keep background tasks within the current execution. A timeout
or exception can follow a partially completed action: inspect state before
retrying. Ordinary code errors preserve the session for correction.

If the owned tab is closed or the browser restarts, close the stale session and
start a new one. If desktop startup fails, check the Nix-owned `cua-driver` and
`sway` user services. Browser connectivity is at `http://127.0.0.1:19222`.
The desktop services and driver own the display setup; agents need no ad-hoc
Wayland environment exports or profile copies.

Finish with `computer_close(session=...)`. Verify the actual outcome before
claiming success. Runtime details and measured acceptance results live in
`~/Documents/Git/nix/hosts/spark/docs/browser.md`.
