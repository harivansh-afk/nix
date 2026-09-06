# Spark browser and desktop automation

Use the `computer` MCP server for browser and desktop tasks on Spark. It exposes
`computer_exec` and `computer_close`: persistent Python with Playwright for pages,
and Cua Driver for native windows. The implementation is
[`pkgs/spark-computer/server.py`](../../../pkgs/spark-computer/server.py); the
agent workflow is the [`spark-computer` skill](../../../dots/agents/skills/spark-computer/SKILL.md).

Nix configures this same server for Codex, Claude Code, omp and Hermes on Spark.
Each harness starts its own stdio process; Python sessions are local to that
process. They share the original Chromium profile, the CUA service and a native
input lock. This configuration does not install a browser server on the Mac.
Run the Spark harness remotely when working from there.

## A browser task

Call `computer_exec` with a unique `session` and Python `code`. Imports and
variables persist across calls using that session. Top-level `await` works:

```python
page = await browser.page()
await page.goto("https://example.com")
print(await page.title())
display(await page.screenshot())
```

`browser.page()` creates one task-owned tab in the original Chromium context,
attached through `http://127.0.0.1:19222`. It retains that page object and refuses
a closed/disconnected tab instead of selecting another tab. Use Playwright
locators, DOM state and assertions for ordinary controls; use screenshots for
visual checks, canvas and uncertain page state. `display(bytes_or_path)` returns
an MCP image block. Printing a filename or base64 does not show the model pixels.

`await browser.tabs()` lists titles, URLs and whether each tab belongs to this
session. When the task explicitly concerns an existing tab, select its exact
page from `page.context.pages` using the observed metadata and retain that
reference. Preserve unrelated tabs. The helper owns only the tab it created;
close any additional tabs or contexts you create yourself.

Finish with `computer_close(session="the-same-name")`. It closes the owned tab,
ends the session's CUA connection and discards Python state. Chromium and other
tabs stay open. Session names separate variables and owned tabs; cookies,
local storage and account state remain shared. Coordinate conflicting work on
the same site/account.

## A native desktop task

Set `desktop: true` on `computer_exec` whenever using `desktop`. This holds a
file lock at `/run/user/<uid>/spark-computer.lock` for the whole execution,
serializing native work across participating MCP processes. Browser-only calls
can run concurrently. Direct CUA clients and Hari's VNC input do not take this
lock; yield when Hari takes over.

```python
print(await desktop.list_windows())
print(await desktop.describe("get_window_state"))
```

Select the exact `pid` and `window_id` from current discovery. A snapshot returns
structured state and forwards any image blocks automatically:

```python
state = await desktop.get_window_state(pid=PID, window_id=WINDOW_ID)
print(state)
```

Inspect `await desktop.describe("tool_name")` before an unfamiliar action. Use a
fresh `element_token`, or its matching `snapshot_id` and `element_index`, for
semantic actions. Window screenshots define window-local coordinates; desktop
screenshots define display coordinates. Retain source dimensions if a harness
resizes the image. Verify the resulting application state after every action;
a tool success or `effect: unverifiable` is not proof of completion.

Sway supports accessibility actions, capture and foreground input. Arbitrary raw
keyboard/pointer injection into an occluded window remains unavailable through
its shared seat. Use `delivery_mode="foreground"` when the task requires that
route, and coordinate the visible focus change. Read the installed upstream
`cua-driver/LINUX.md` for action-specific limits. The compositor experiment and
its actual Chromium results are recorded in [the research note](browser-research.md).

## Runtime ownership

[`desktop.nix`](../services/desktop.nix) starts headless Sway with pixman. Sway
imports `WAYLAND_DISPLAY`, `SWAYSOCK` and `XDG_CURRENT_DESKTOP` into the user
manager, then starts the Chromium, WayVNC and CUA user services. Chromium uses
native Wayland, renderer accessibility, the original mutable profile and the
loopback debugging port. Its service restores the prior session on startup.

For the first migration to `chromium.service`, stop the old browser owner and
let its Chromium process exit before starting the new service. Chromium's
single-instance handoff otherwise sends the launch to the old process, leaving
the new unit without ownership. Preserve the original profile and coordinate
this restart with active tasks. Verify the new unit's `MainPID` owns Chromium
and the CDP listener; package installation alone does not transfer ownership.

CUA listens at `/run/user/<uid>/cua-driver/control.sock` in a mode-0700 runtime
directory. The MCP bridge explicitly runs `cua-driver mcp --socket <that-path>`;
it connects to the existing service. Bare `cua-driver mcp` on Linux owns another
runtime. The packaged CUA executable wraps `swaymsg`, `wtype` and `grim` onto PATH,
so its service and subprocess clients have the same required helpers.

Normal MCP calls need no manual display exports. `SPARK_BROWSER_CDP` and
`CUA_DRIVER_SOCKET` are explicit endpoint overrides for controlled tests; their
defaults are set by [`spark-computer`](../../../pkgs/spark-computer/default.nix).
Keep `~/.config/chromium` private and mutable. Change launch configuration in Nix;
changed browser flags require a browser restart and therefore coordination with
active browser work.

Hermes uses `mcp__computer__computer_exec` and `mcp__computer__computer_close` for
both CLI and Photon. Its separate `browser` and `computer_use` toolsets are
disabled in [`hermes.nix`](../services/hermes.nix), so it uses the same controller
as the coding agents. The package applies a focused MCP image patch: cached
screenshots retain adapter `MEDIA:` references and become native image content
for vision-capable model requests. Error results can retain images too. The
patch uses Hermes' existing image preparation and can resize images; do not
infer source pixel coordinates from the displayed dimensions alone. Actual Astra
image receipt has been verified in the fixture runs below.

## Diagnosis and recovery

Inspect the actual service and endpoint before changing anything:

```sh
systemctl --user status sway chromium cua-driver wayvnc --no-pager
systemctl --user show-environment | rg '^(WAYLAND_DISPLAY|SWAYSOCK|XDG_CURRENT_DESKTOP)='
curl --fail --silent --show-error http://127.0.0.1:19222/json/version
cua-driver call list_windows '{}' --socket "/run/user/$(id -u)/cua-driver/control.sock"
journalctl --user -u cua-driver -u chromium --since '10 minutes ago' --no-pager
```

If Sway's display is ready but the newly deployed service has not started,
`systemctl --user start cua-driver` starts the declared unit. Do not create an
ad-hoc daemon to hide a service failure. Inspect the journal and generated unit
when a helper or socket is missing. X11-oriented `doctor` warnings alone do not
diagnose native Wayland; window discovery, pixels and observed actions do.

A code exception preserves session variables for correction. Timeouts are
cooperative and cannot interrupt blocking Python; use async APIs and keep
background work inside the current execution. A failed/timed-out call may have
partially acted, so observe before retrying. After browser or CUA transport loss,
close the stale session and start a new one. An idle MCP process restart also
loses its Python namespace.

The standard limit is 60 seconds per execution, configurable from 1 to 120.
Each process holds at most 16 sessions. Each call returns at most eight images
and 20 MiB of encoded image data; text is capped at 64 KiB. This runs trusted
Python as Hari, with normal imports and filesystem access; it is not a sandbox.

## Acceptance status

On 2026-09-06, the packaged shared runtime passed these Spark checks:

| Check | Observed result |
|---|---|
| Browser acceptance script | Passed in 3.94 s: form, delayed control, canvas, download, retained draft and Python variables, separate sessions and cleanup; all pre-existing tabs preserved |
| Cross-process coordination | Synthetic lock test passed; cooperating server processes serialized access |
| Actual Codex, Astra High | Passed in 30.7 s: read an unpredictable seven-character marker available only in screenshot pixels, retained a variable across two calls, closed its session; CDP independently confirmed tab removal |
| Actual patched Hermes, Astra High | Passed in 26.93 s: screenshot-only marker identified, persistent state and cleanup verified; request evidence contained one native input image and confirmed model/effort |
| Real native GTK fixture | Reproducible test passed in 1.43 s: semantic set-value/button and foreground select-all, typing and pixel-button actions changed independent app-owned JSON; images inspected; fixture stopped |
| Chromium service lifecycle | Source-generated unit owned the browser; SIGTERM triggered one automatic restart, CDP returned on loopback, and all three tabs restored their origins, paths and fragments |
| Browser acceptance after restart | Passed again in 4.70 s; all three pre-existing tab URLs stayed unchanged during the test |
| Runtime/image regression checks | 31 focused tests and 138 upstream Hermes tests passed |

The browser script is
[`test_acceptance.py`](../../../pkgs/spark-computer/test_acceptance.py); the native
check is [`test_native.py`](../../../pkgs/spark-computer/test_native.py). Fixtures and focused tests are under
[`pkgs/spark-computer`](../../../pkgs/spark-computer). The model trials used
temporary local fixtures and the original browser through the packaged bridge.
These are single fixture runs, not comparative latency or model benchmarks.
They do not certify every website, native application or harness configuration.

The configuration builds. Source-generated Chromium and CUA units are active
through runtime-only user-systemd links. Chromium ownership and restart recovery
have been checked: the service owns the browser, `NRestarts` increased to one,
and its CDP listener returned on loopback. All three tab origins, paths and
fragments were restored; one site's query string changed on reload, so this is
not byte-identical URL restoration. The subsequent browser acceptance preserved
all three existing URLs throughout its own run.

The full Sway configuration and all-harness configuration have not been globally
deployed, and the PR is unmerged. Runtime-unit acceptance and temporary model
configuration do not establish those separate delivery steps.

## Reproduce the fixture checks

From this repo, build the bridge and its matching Python environment without
installing anything into the user profile:

```sh
nix build --impure --expr 'let f = builtins.getFlake ("git+file://" + toString ./.); in import ./pkgs/spark-computer { pkgs = f.nixosConfigurations.spark.pkgs; }' --out-link /tmp/spark-computer-check
nix build --impure --expr 'let f = builtins.getFlake ("git+file://" + toString ./.); in (import ./pkgs/spark-computer { pkgs = f.nixosConfigurations.spark.pkgs; }).python' --out-link /tmp/spark-computer-python
export SPARK_COMPUTER_COMMAND=/tmp/spark-computer-check/bin/spark-computer
uv run --no-project --python /tmp/spark-computer-python/bin/python python pkgs/spark-computer/test_acceptance.py
```

The browser script creates its own local HTTP fixture and task tabs, verifies
independent state and cleanup, and prints an artifact directory. It uses an
isolated test lock and sends no native input.

The native test acts on a separately launched, uniquely titled GTK fixture. Run
it when the visible desktop is available for the test, then stop its transient
unit:

```sh
nix build --impure --expr 'let f = builtins.getFlake ("git+file://" + toString ./.); in import ./pkgs/spark-computer/fixtures { pkgs = f.nixosConfigurations.spark.pkgs; }' --out-link /tmp/spark-native-fixture
systemd-run --user --collect --unit=spark-native-acceptance /tmp/spark-native-fixture/bin/spark-computer-native-fixture --state /tmp/spark-native-acceptance.json
uv run --no-project --python /tmp/spark-computer-python/bin/python python pkgs/spark-computer/test_native.py --state /tmp/spark-native-acceptance.json --title 'Spark Computer Acceptance'
systemctl --user stop spark-native-acceptance
```

The fixture launch inherits the user manager's Sway environment. The test uses
its independent JSON state and saves returned screenshots; it leaves the fixture
running so cleanup remains explicit. These scripts exercise the bridge and app
state. They do not replace an actual model screenshot-reading test.
