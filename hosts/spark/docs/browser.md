# Spark browser and desktop

Codex, Claude Code, omp and Hermes use the same `computer` stdio MCP server.
The [shared skill](../../../dots/agents/skills/spark-computer/SKILL.md) owns the
agent workflow; this document covers operation, testing and design evidence.
Each harness starts a process with named Python sessions. Sessions own tabs and
variables, but share Chromium's profile and the desktop. This is not account or
filesystem isolation. Browser work can run concurrently; `desktop=true` locks
one execution across cooperating processes. Human input and direct clients bypass
that lock. Truly parallel native input requires separate desktops.

## Services and recovery

[desktop.nix](../services/desktop.nix) owns Sway, Chromium and CUA. Sway imports
its display/accessibility environment before starting WayVNC, CUA and Beeper,
not Chromium. Chromium starts on demand and a clean close stays closed
(`Restart=on-failure`; crashes still restart). It restores its session and
exposes CDP at `127.0.0.1:19222`; its profile
and GNOME Keyring credentials remain private mutable state. CUA listens at
`/run/user/<uid>/cua-driver/control.sock` in a mode-0700 directory. Its package
supplies `swaymsg`, `wtype` and `grim` on PATH.

The first `browser.page()` or `browser.tabs()` attaches to an already-ready
browser. If the default CDP endpoint is unavailable, the helper runs
`systemctl --user start chromium.service`, then retries CDP within a shared
15-second startup/readiness budget (plus the initial one-second connection
attempt). Startup failure or timeout reports an error, not an ad-hoc browser.
Cancelling a pending start kills and reaps the systemctl client, but does not
undo a service start already submitted to systemd. A timeout likewise does not
stop Chromium or alter other agents' tabs. Calls in one MCP process share a
connection lock; separate processes use systemd's idempotent start.

Only the exact managed endpoint `http://127.0.0.1:19222` can trigger startup.
Other `SPARK_BROWSER_CDP` values are attach-only with a 15-second connection
timeout, including other local ports and WebSocket URLs. Native-only calls and
MCP startup do not launch Chromium. Direct Playwright/CDP clients must start
the service themselves if needed. Manual launch: `systemctl --user start
chromium.service`; explicit stop: `systemctl --user stop chromium.service`.

```sh
systemctl --user status sway chromium cua-driver wayvnc --no-pager
curl --fail --silent --show-error http://127.0.0.1:19222/json/version
cua-driver call list_windows '{}' --socket "/run/user/$(id -u)/cua-driver/control.sock"
journalctl --user -u cua-driver -u chromium --since '10 minutes ago' --no-pager
```

For the first migration, stop the old Chromium owner before starting
`chromium.service`; otherwise its singleton handoff leaves the new service
without ownership. Coordinate restart with active tasks, retain the profile,
and verify the service's `MainPID` owns the browser and CDP listener.
Change launch configuration in Nix. After a browser/transport restart, agents
must close stale sessions and create new ones. Do not hide service failures with
ad-hoc daemons. The bridge explicitly connects to the shared CUA socket;
bare `cua-driver mcp` otherwise starts its own runtime.

Hermes needs neither display environment discovery nor a Sway startup gate:
its browser and desktop calls use CDP and the shared CUA socket. Its separate
native toolsets are disabled. Hermes runs unpatched upstream: MCP screenshots
arrive as `MEDIA:` references; `vision_analyze` loads that path into the model's
image context using upstream image processing. Coding harnesses can consume MCP
images directly. Account for image resizing when choosing pixel coordinates.
If a failed call has no usable screenshot reference, capture fresh state in a
successful call before interpreting it.

Calls default to 60 seconds, maximum 120; all harness deadlines allow 180.
There are at most 16 sessions per process. Output is bounded to 64 KiB of text
and eight images / 20 MiB encoded. Failure diagnostics have a separate 4 KiB
budget, so full stdout cannot hide an error, cancellation or execution deadline.
An inner Python `TimeoutError` retains its message instead of being mislabeled
as the execution deadline. Timeouts are cooperative, not a Python sandbox.

## Validation

CI retains the repository's flake/lint checks and packaged Hermes/Photon startup
check. `nix build .#checks.aarch64-linux.spark-computer` runs offline lifecycle
regressions with mocked CDP and systemctl: ready/cold start, concurrent callers,
failure, timeout, cancellation, custom endpoints, reconnection and tab ownership.
It also covers diagnostic limits, inner versus execution timeouts, cancellation,
persistent variables, overlap rejection and the desktop opt-in gate. It never
starts the live browser. The earlier browser/native trials were temporary
experiments, not ongoing regression coverage.

Historical trials covered browser forms, screenshots, tab cleanup and native
input, but do not replace a post-deployment lifecycle smoke test. When deployment
is explicitly approved, close the last Chromium window, confirm the service stays
inactive, then request a new browser session and verify CDP readiness and owned-tab
cleanup. Do not run that live trial while the user wants Chromium closed.

## Design evidence

### Optional agent-browser CLI

[agent-browser](https://agent-browser.dev) is a native Rust CLI/daemon using
direct CDP, not a replacement for CDP. Its compact accessibility snapshots and
element refs are useful for shell-oriented agents. [CDP mode](https://agent-browser.dev/cdp-mode)
attaches to an existing logged-in browser; [sessions](https://agent-browser.dev/sessions)
with strict `--pin-tab` support concurrent tab isolation. Without pinning, a
client can navigate a shared active tab. No cookie export or copied profile is
needed for attaching to Spark's browser.

Keep it an optional alternative, not another default daemon or dependency in
this lifecycle fix. The pinned nixpkgs offers agent-browser 0.27.0 for
aarch64-linux; current upstream documentation does not establish that this older
package supports every documented flag. No matched Spark task benchmark establishes superiority
over the current persistent async Playwright sessions, owned tabs and shared
CUA desktop path. Compact snapshot claims do not compare against this facade's
selective printed output. Any future CLI integration should retain explicit tab pinning,
the managed startup boundary and owned-tab-only cleanup. Native app automation
still needs CUA; this PR does not change that interface.

OpenAI recommends code execution for Astra computer use. Persistent Python lets
the task model group async Playwright operations and inspect native screenshots
without a second autonomous agent. Semantic controls and visual reasoning are
complementary. [Official guide](https://developers.openai.com/api/docs/guides/tools-computer-use),
[integration recipes](https://developers.openai.com/api/docs/guides/tools-computer-use-integration).
CDP preserves the existing browser identity but has lower fidelity than
Playwright's own connection protocol. [Playwright contract](https://playwright.dev/docs/api/class-browsertype#browser-type-connect-over-cdp).

The research compared agent-browser 0.36.0, Playwright's extension, DevTools MCP
1.8.0 and browser-harness. These are credible alternatives, not evidence that
another command layer improves this workload. Tab ownership follows the same
principle as [agent-browser tab pinning](https://github.com/vercel-labs/agent-browser/blob/v0.36.0/README.md#tab-pinning)
and [Playwright client groups](https://github.com/microsoft/playwright/tree/main/packages/extension#multiple-clients).
See also [DevTools concurrent sessions](https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/chrome-devtools-mcp-v1.8.0/README.md#concurrent-sessions)
and [browser-harness](https://github.com/browser-use/browser-harness/blob/main/SKILL.md).

A nested Cua compositor was built and tested on Spark with disposable Chromium
profiles. Its direct socket delivered background input to an occluded canvas:
app events and screenshot confirmed the change, while the foreground canary
received no input. Driver 0.23.2's public interface failed the same pixel click,
refused window capture with `surface_identity_unproven`, and reported failure
after typing actually occurred. This supports further isolated-desktop research,
but not replacing Sway's working path yet. [Cua compositor](https://github.com/trycua/cua/tree/cua-driver-rs-v0.23.2/libs/cua-driver/rust),
[Hyprland input experiment](https://github.com/trycua/cua/pull/3572),
[observation experiment](https://github.com/trycua/cua/pull/3557).

Beta status is not the selection criterion; observed task behavior is. A global
performance claim needs matched models, effort, tasks, budgets and independent
outcome grading. Published scores are not Spark measurements.
[OSWorld V2](https://github.com/xlang-ai/OSWorld-V2).
