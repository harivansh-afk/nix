# Astra browser and computer-use architecture

Research and isolated compositor trials: 2026-09-06. Target: Spark,
NixOS/aarch64, original headed Chromium and native Sway. This note describes the
implemented architecture and its evidence, including real model/browser/native
fixture runs and Chromium lifecycle recovery. Global deployment remains pending.
It does not claim a measured global performance ranking.

## Selected architecture

Expose persistent Python through a two-tool stdio MCP server. Keep Playwright's
async API for browser code and Cua Driver's upstream MCP interface for native
windows. Return actual images alongside structured state. Codex, Claude Code,
omp and Hermes use this same `computer` server on Spark; each harness owns a
separate server process. The implementation is
[`server.py`](../../../pkgs/spark-computer/server.py), with the operating contract
in [browser.md](browser.md).

This follows OpenAI's current recommendation to use code execution for Astra
computer use. Existing function/MCP integrations remain valid; the structured
`computer` tool is an alternative. The local application still owns browser and
desktop execution. [Official computer-use guide](https://developers.openai.com/api/docs/guides/tools-computer-use)

The official examples combine DOM/locator operations, page text, screenshots
and scripts. Thus visual reasoning does not require abandoning reliable semantic
controls. Screenshots must reach the model as images; resizing requires a
coordinate mapping. The Linux PyAutoGUI example uses X11 and does not establish
Sway support. [Integration recipes](https://developers.openai.com/api/docs/guides/tools-computer-use-integration)

The bridge attaches to Nix Chromium over its explicit loopback CDP endpoint.
Each Python session creates and retains one owned tab in the original context;
it fails on tab loss rather than falling back to another user's tab. Cookies
and account state remain shared. Native calls explicitly connect to the
Nix-owned CUA daemon and take a file lock across cooperating server processes.
This is coordination, not desktop/account isolation.

The model's normal coding harness remains the task owner. No second autonomous
browser agent is needed. MCP packages a small code surface for multiple harnesses;
it is not itself a speed or quality claim. CDP attachment also has lower fidelity
than Playwright's own protocol, so advanced operations need actual Spark tests.
[Playwright CDP contract](https://playwright.dev/docs/api/class-browsertype#browser-type-connect-over-cdp)

## Integration details that matter

The packaged CUA 0.23.2 executable now carries `swaymsg`, `wtype` and `grim` on
PATH. This corrects the earlier mismatch between an interactive test daemon and
the generated service environment. Upstream shells out for Sway metadata/focus,
keyboard input and fallback capture. [Pinned Sway adapter](https://github.com/trycua/cua/blob/cua-driver-rs-v0.23.2/libs/cua-driver/rust/crates/platform-linux/src/wayland/sway_ipc.rs),
[pinned Wayland backend](https://github.com/trycua/cua/blob/cua-driver-rs-v0.23.2/libs/cua-driver/rust/crates/platform-linux/src/wayland/mod.rs)

The bridge's `desktop` helper owns a persistent CUA MCP connection explicitly
pointing at `/run/user/<uid>/cua-driver/control.sock`. This avoids assuming that
bare Linux `cua-driver mcp` shares an existing daemon. Upstream's 0.23.2 CLI also
preserves explicit non-default session labels across one-shot calls, despite
conflicting skill wording; it is incorrect to claim every CLI action loop is
broken. Tokens still expire on relevant re-snapshots or runtime replacement.
[Pinned CLI lifecycle](https://github.com/trycua/cua/blob/cua-driver-rs-v0.23.2/libs/cua-driver/rust/crates/cua-driver/src/cli.rs#L2255),
[token registry](https://github.com/trycua/cua/blob/cua-driver-rs-v0.23.2/libs/cua-driver/rust/crates/cua-driver-core/src/element_token.rs)

Hermes uses the same server for CLI and Photon; its independent browser and
computer-use toolsets are disabled. The local
[`MCP image patch`](../../../pkgs/spark-computer/hermes-mcp-images.patch) addresses
a specific observation gap: caching a screenshot and returning a `MEDIA:` path
does not make it model-visible. The patch retains those adapter references while
attaching native image content for vision-capable requests, including error
observations. Its fallback preserves text if native attachment is unavailable.
Actual Astra model receipt was checked separately from source/unit behavior: the
Hermes trial below includes native input-image evidence.

## Other browser candidates

The research considered current releases and beta/research routes. Eligibility
does not depend on a stable label; suitability depends on the workload and the
observed behavior.

| Candidate | Relevant capability | Why it is not the default interface here |
|---|---|---|
| agent-browser 0.36.0 | Persistent Rust/CDP daemon and explicit tab pinning | Useful shell alternative; the shared runtime directly provides Python variables, Playwright and image blocks |
| Playwright CLI/extension | Multi-step code and client tab ownership | Credible comparison candidate; requires its own attachment/extension lifecycle |
| Chrome DevTools MCP 1.8.0 | Page-ID routing and detailed browser diagnostics | Good specialist tooling; a broad diagnostics surface does not establish better ordinary task completion |
| browser-harness | Python/CDP controller for existing coding agents | Another plausible code runtime; default mutable current-tab state requires coordination |

Agent-browser's released `--pin-tab` contract creates a new tab and refuses a
lost target; this is a useful design comparison, not cookie isolation. Its
installer rejects Linux aarch64 and points users to system Chromium. The release
has ARM64 CLI binaries, so browser installation and CLI availability must be
separated. [Tab contract](https://github.com/vercel-labs/agent-browser/blob/v0.36.0/README.md#tab-pinning),
[installer](https://github.com/vercel-labs/agent-browser/blob/v0.36.0/cli/src/install.rs)

Playwright's extension documents separate client tab groups in a shared profile.
DevTools 1.8.0 enables page-ID routing by default, even though some unversioned
pages still describe it as experimental. Browser-harness documents its default
current-tab concurrency constraint. These source contracts motivate exact page
references in the selected runtime; none is a matched Astra benchmark.
[Extension ownership](https://github.com/microsoft/playwright/tree/main/packages/extension#multiple-clients),
[DevTools release](https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/chrome-devtools-mcp-v1.8.0/README.md#concurrent-sessions),
[browser-harness skill](https://github.com/browser-use/browser-harness/blob/main/SKILL.md)

## Compositor experiment: a real gain and real integration gaps

Sway remains the original desktop. It provides useful accessibility actions,
capture and foreground input; it cannot deliver arbitrary raw input to an
occluded surface through an independent seat. [Tagged Linux support](https://github.com/trycua/cua/blob/cua-driver-rs-v0.23.2/libs/cua-driver/rust/Skills/cua-driver/LINUX.md)

The nested `cua-compositor` was actually built and tested on Spark. Its tagged
Nix recipe patches wlroots 0.19 tinywl and exposes direct surface input through
`CUA_INJECT_SOCKET`. The trial used Driver 0.23.2 and Chromium 149.0.7827.114 with
a private Wayland runtime, private D-Bus, disposable profiles and local canvas
fixtures. Original Sway windows and the original Chromium profile were untouched.
[Recipe](https://github.com/trycua/cua/blob/cua-driver-rs-v0.23.2/nix/cua-driver/compositor/default.nix),
[compositor protocol](https://github.com/trycua/cua/blob/cua-driver-rs-v0.23.2/nix/cua-driver/compositor/cua_compositor_patch.py)

| Observed on Spark | Result |
|---|---|
| Two native Chromium windows and full-output capture | Passed; rendered PNGs inspected |
| Direct compositor raw click into the occluded target | Canvas counter changed 0 to 1; app event and later revealed screenshot agreed |
| Focus and input leakage | Before/after compositor queries kept the other window foreground; no canary app events |
| Public Driver background pixel click | No app click; returned accessibility route with unverifiable effect |
| Public Driver background typing | Target received the requested ASCII keys while occluded, despite a delivery-failed escalation result |
| Public Driver target-window screenshot | Refused with `surface_identity_unproven` |
| Public Driver held-button pair | Returned `held:false`; no demonstrated effect |

This establishes a useful research capability beyond stock Sway. It also shows
why replacing Sway would not yet improve the normal agent workflow: the working
pointer experiment bypassed the public Driver tool contract, and target capture
failed. The appropriate next experiment is a repair and retest of those exact
routes in an optional isolated desktop. Beta status is not the objection.

Two small scripted trials do not certify Electron, arbitrary Chromium apps,
Unicode, gestures, fault recovery or transient focus isolation. The second trial
ran for 10.945 seconds including setup and cleanup initiation; this is not an
agent latency comparison. HTTP events verified characters received but do not
prove their order because requests can arrive concurrently. Trial processes
exited. Temporary evidence was recorded under `/tmp/cua-nested-experiment/`;
those files are not durable repository artifacts. The built compositor's SHA256
was `c323efe0f1c2bd606d0172a372c2cc4a3dbf235c3c1e340a56b7e6d29c55fd9c`.

Hyprland also merits research consideration. Its September 6 isolated-input
experiment reports independently checked Calc/Inkscape file changes and multiple
Driver runtimes. It explicitly excludes Chromium/Ozone and Electron coverage.
The related observation branch's canonical native suite stops at the
foreground-key preflight. These workload gaps, rather than release labels,
made nested Cua the stronger immediate Chromium experiment. Neither branch's
changes are contained in published Driver 0.23.2.
[Hyprland input experiment](https://github.com/trycua/cua/pull/3572),
[observation branch](https://github.com/trycua/cua/pull/3557)

## Measured acceptance and remaining work

The packaged bridge passed a real original-browser fixture run in 3.94 seconds:
form and delayed-control interaction, canvas, download verification, draft and
Python state, multiple sessions, tab cleanup and preservation of all existing
tabs. A separate synthetic cross-process lock check passed. The reproducible
browser script is [`test_acceptance.py`](../../../pkgs/spark-computer/test_acceptance.py).

An actual Codex session using Astra High read an unpredictable seven-character
marker supplied only through screenshot pixels, retained a Python variable
across two executions, then closed its session. Runtime records confirmed the
model and effort; native MCP image content was recorded, and independent CDP
inspection confirmed tab cleanup. This one run took 30.7 seconds.

An actual patched Hermes Astra High run passed the same kind of visual,
persistence and cleanup check in 26.93 seconds. Captured request evidence
confirmed the model/effort and one native input image. This tests the image patch
through the model request, rather than assuming a cached MEDIA path is enough.

The reproducible [`native GTK test`](../../../pkgs/spark-computer/test_native.py)
passed in 1.43 seconds: semantic set-value/button actions, foreground select-all,
typing and a pixel-button action. Independent application JSON and inspected
screenshots confirmed effects; the fixture was stopped afterward. The
runtime/image checks passed 31 focused tests, and the Hermes patch passed 138
upstream tests.

These times are single fixture-run measurements, not a controlled comparison
between harnesses or models. The results establish useful browser, native and
visual capability in the tested configuration. They do not certify arbitrary
apps or turn upstream benchmark scores into local performance results.

Chromium lifecycle acceptance also passed. After the old browser owner exited,
the source-generated `chromium.service` owned the new process. SIGTERM produced
one automatic restart, the CDP listener returned on loopback, and all three tabs
restored their origins, paths and fragments. One site changed its query string
on reload; byte-identical URL restoration is not claimed. Browser acceptance
then passed again in 4.70 seconds, preserving all three pre-existing URLs during
that test.

The configuration builds; source-generated Chromium and CUA units are active
through runtime-only user-systemd links. Full Sway and all-harness configuration
have not been globally deployed, and the PR is unmerged. See
[the operations note](browser.md) for ownership, reproduction commands and these
separate delivery states.

For comparative claims, use identical model/effort, tasks, initial state and
budgets; measure completed outcomes, wall time, tool/token counts, wrong-target
actions, recovery and intervention. Include browser forms, tab ownership,
canvas and native-dialog tasks. Grade app/file state independently. OSWorld V2
likewise distinguishes task outcomes and intermediate progress and requires
coordinated benchmark releases; published model scores cannot be transplanted
onto this unmeasured local stack. [OSWorld V2](https://github.com/xlang-ai/OSWorld-V2)

The implemented choice is a shared code-and-vision interface with proven upstream
controllers and explicit local ownership. The isolated compositor results guide
further work; they do not establish that this stack is globally state of the art.
