---
name: spark-computer
description: Use Spark's browser or desktop for websites, screenshots, visual checks, native apps and dialogs.
---

# Spark computer

Use the `computer` MCP server's `computer_exec` and `computer_close` tools.
Hermes prefixes these with `mcp__computer__`. Give each task a unique `session`;
Python variables, imports and page references persist across calls in that session.

## Browser

Use async Playwright with top-level `await`:

```python
page = await browser.page()
await page.goto("https://example.com")
print(await page.title())
display(await page.screenshot())
```

The helper creates one owned tab in Hari's existing Chromium profile. Use
observed roles, labels and DOM state for controls; screenshots for canvas and
visual checks. Group known steps and wait on specific locators/events rather
than sleeping. `display(image_bytes_or_path)` emits an MCP image. In Hermes,
pass the path after `MEDIA:` to its separate `vision_analyze` tool as `image_url`,
with a `question` describing what to inspect. This loads the screenshot into
your visual context; a file path alone is not a visible image. Other harnesses
can display MCP images directly.

`await browser.tabs()` lists tab metadata. When explicitly asked to operate an
existing tab, resolve its exact reference from `page.context.pages`. Preserve
unrelated tabs. Sessions share cookies, storage and account state: coordinate
conflicting work on the same site. Extra pages or isolated contexts are your
responsibility to close; isolated contexts do not inherit the existing login.

## Desktop

Set `desktop: true` when using `desktop`. Each execution holds a shared lock
across participating agents; browser-only calls can continue independently.
Keep dependent observation/action/verification steps together under that lock.
Human input and direct clients bypass it; yield when Hari takes over.

```python
print(await desktop.list_windows())
print(await desktop.describe("get_window_state"))
```

Select the exact window's observed `pid` and `window_id`, then call
`await desktop.get_window_state(pid=PID, window_id=WINDOW_ID)`. CUA screenshots
use the same image route above. Discover unfamiliar action schemas with
`await desktop.describe("tool_name")`, then call `await desktop.tool_name(...)`.

Prefer fresh accessibility `element_token` values (or matching snapshot/index).
Use `delivery_mode="foreground"` for visible input when needed. Window actions
use window-local screenshot coordinates; account for harness image resizing.
Reobserve after actions and after reacquiring the lock. Verify application state;
`effect: unverifiable` does not establish success. For refused native actions,
read the adjacent `cua-driver/LINUX.md`. Sway cannot independently inject raw
input into an occluded window.

## Finish and recover

Use async APIs and keep background tasks within the call. Timeouts are cooperative;
blocking Python cannot be interrupted. Errors preserve variables but may follow
partial actions: inspect before retrying. After tab loss or a browser/transport
restart, close the stale session and start another.

Finish with `computer_close(session=...)`; it closes the owned tab and CUA
connection, preserving Chromium and other tabs. For service failures and test
commands, read `~/Documents/Git/nix/hosts/spark/docs/browser.md`.
