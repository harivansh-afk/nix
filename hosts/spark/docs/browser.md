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
native toolsets are disabled. The [image patch](../../../pkgs/spark-computer/hermes-mcp-images.patch)
turns cached MCP images into native model input while retaining media references
and error semantics. It uses upstream image preparation, including resizing;
map displayed coordinates to original screenshot dimensions. Remove the patch
when the pinned upstream provides equivalent support.

Calls default to 60 seconds, maximum 120; all harness deadlines allow 180.
There are at most 16 sessions per process. Output is bounded to 64 KiB of text
and eight images / 20 MiB encoded. Timeouts are cooperative, not a Python sandbox.

## Tests

CI runs [runtime tests](../../../pkgs/spark-computer/test_server.py),
[Hermes image regressions](../../../pkgs/spark-computer/test_hermes_images.py)
and packaged Hermes/Photon startup checks. Manual acceptance uses real Spark
services, disposable pages and an independently observable GTK fixture:

```sh
nix build --impure --expr 'let f = builtins.getFlake ("git+file://" + toString ./.); in import ./pkgs/spark-computer { pkgs = f.nixosConfigurations.spark.pkgs; }' --out-link /tmp/spark-computer-check
nix build --impure --expr 'let f = builtins.getFlake ("git+file://" + toString ./.); in (import ./pkgs/spark-computer { pkgs = f.nixosConfigurations.spark.pkgs; }).python' --out-link /tmp/spark-computer-python
export SPARK_COMPUTER_COMMAND=/tmp/spark-computer-check/bin/spark-computer
uv run --no-project --python /tmp/spark-computer-python/bin/python pkgs/spark-computer/test_acceptance.py
```

The browser test covers forms, delayed controls, canvas, downloads, draft state,
persistent sessions, tab cleanup and a separate-process lock. It uses its own
local HTTP fixture and test lock, with no native input. For native acceptance,
use the visible desktop only when available for a test:

```sh
nix build --impure --expr 'let f = builtins.getFlake ("git+file://" + toString ./.); in import ./pkgs/spark-computer/fixtures { pkgs = f.nixosConfigurations.spark.pkgs; }' --out-link /tmp/spark-native-fixture
systemd-run --user --collect --unit=spark-native-acceptance /tmp/spark-native-fixture/bin/spark-computer-native-fixture --state /tmp/spark-native-acceptance.json
uv run --no-project --python /tmp/spark-computer-python/bin/python pkgs/spark-computer/test_native.py --state /tmp/spark-native-acceptance.json
systemctl --user stop spark-native-acceptance
```

The native test verifies semantic and foreground keyboard/pixel actions against
app-owned JSON, saves screenshots, and leaves fixture shutdown to the caller.

Initial acceptance on 2026-09-06:

| Check | Result |
|---|---|
| Actual Codex / Hermes Astra High | Both read pixel-only random markers, reused Python variables and closed their tabs; native image delivery confirmed |
| Browser / native fixtures | Passed; pre-existing browser tabs preserved; native JSON and screenshots verified |
| Chromium lifecycle | Service owned the browser, restarted after SIGTERM and restored three tab locations; one site changed its query string on reload |
| Regression checks | 19 runtime, 12 image and 138 upstream Hermes tests passed |

The initial service tests used runtime-only systemd links and temporary harness
configuration. They did not deploy the full system. Fixture success is not a
comparative benchmark or proof of every application's behavior.

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
