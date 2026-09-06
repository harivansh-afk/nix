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
its display/accessibility environment before starting the user services.
Chromium restores its session and exposes CDP at `127.0.0.1:19222`; its profile
and GNOME Keyring credentials remain private mutable state. CUA listens at
`/run/user/<uid>/cua-driver/control.sock` in a mode-0700 directory. Its package
supplies `swaymsg`, `wtype` and `grim` on PATH.

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
and eight images / 20 MiB encoded. Timeouts are cooperative, not a Python sandbox.

## Validation

CI retains the repository's flake/lint checks and packaged Hermes/Photon startup
check. This PR adds no test files. Browser/native fixtures and model comparisons
were run temporarily on Spark; they are validation evidence, not ongoing regression
coverage.

Initial acceptance on 2026-09-06 verified real browser forms, delayed controls,
canvas, downloads, persistent sessions, tab cleanup and cross-process locking.
Native accessibility and foreground keyboard/pixel actions were checked against
app-owned JSON and screenshots. Chromium restarted after SIGTERM and restored
three tab locations; one site changed its query string during reload. These
service trials used runtime-only systemd links, not a full system deployment.

### Hermes image comparison

On upstream `c5594ec` (2026-09-06), three matched pairs used the same browser
screenshots, prompt, Astra High and available `computer`/`vision` tools. Each task
read an image-only random marker, reused Python state and closed its owned tab.

| Route | Correct tasks | Tool calls / model requests per task | Median wall time |
|---|---|---|---|
| Unmodified upstream + `vision_analyze` | 3/3 | 5 / 6 | 32.43 s |
| Local automatic-image patch + vision available | 3/3 | 5 / 6 | 33.66 s |

The five calls included discovery, two code executions, vision and cleanup.
Request metadata confirmed Astra High and native image input. Patched runs still
called `vision_analyze`, retaining two copies of the screenshot in subsequent
model requests; upstream retained one. The patch saved no turns here, so it and
its package override were removed. This small sample supports the existing route
for this task, not a general reliability or speed ranking. Temporary credentials
were deleted and all task tabs closed. No upstream endorsement is inferred.

## Design evidence

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
