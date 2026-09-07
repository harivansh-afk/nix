# Conversation plugin evaluation

Measured on Spark, September 7, 2026, with upstream Hermes
`c5594ec4b34097cafbe24deb6dfd9ac4b21d411d`. The Nix pin is unchanged.
The conversation model was `gpt-6-astra` at medium reasoning; native delegated
workers used the same model at low reasoning. Provider request traces confirmed
both effort settings. The auxiliary summary route is configured as Astra low.

The harness used fresh private Hermes homes, the production OAuth provider and
read-only fixture tools. It loaded the actual plugin through Hermes discovery,
including the `nix-managed-*` directory naming used by activation. It did not
start a gateway, touch an LMS, connect to production MCP servers or send messages.
Native completion events were supplied back to the conversation by the harness.

## Results

These are individual smoke runs, not percentiles or a reliability benchmark.
Times measure complete foreground turns, including provider calls and local tools.

| Scenario | Observed result | Seconds |
|---|---|---:|
| Greeting | Short greeting, no tools | 2.9 |
| Initial course-review handoff, tool search off | Confirmed dispatch, then model reply | 16.1 |
| Unrelated question while that worker was blocked | Correct draft-versus-merged PR explanation | 4.6 |
| Correct running review to physics only | Native steer accepted; no other course records read | 8.6 |
| Deliver corrected worker result | Correct due date, topic and unsubmitted status | 4.6 |
| Long dialogue, built-in compressor, tool search off | Correct recent project name; 36,888 input tokens | 3.6 |
| Same dialogue, conversation engine | Correct project name; 6,226 input tokens | 2.2 |
| Recall after background summary | Correct Juniper release name; deployment approval still pending | 4.2 |
| Full background pool | Admission rejected, zero new workers or fixture reads; honest model reply | 14.2 |

An earlier handoff run took 20.7 seconds, with the unrelated question answered in
3.8 seconds. An earlier correction run took 14.1 seconds to hand off, 5.9 seconds
for the unrelated answer and 7.4 seconds to steer. An earlier long-history pair
was 9.6 versus 2.2 seconds (37,260 versus 6,224 input tokens). Provider variation
is substantial: fewer input tokens are demonstrated; a universal speedup is not.

The final admission-guard regression run also passed: handoff 15.3 seconds,
unrelated answer 5.0 seconds, physics-only steering 13.5 seconds and result reply
4.6 seconds. No non-physics records were read after the correction.

Initial handoffs remain slower than conversational replies because they require
model/tool/model round trips and worker construction. This work does not establish
a sub-second or five-second response guarantee.

## Feedback and changes

- The first harness invocation failed before model execution because SessionDB
  requires a Path. The harness now also cleans its copied credential on error.
- The fixture initially returned null for worker AGENTS.md reads, causing extra
  calls. It now serves the same Nix-owned worker instructions as the workspace.
- Request observers originally saw pre-middleware schemas. Observation moved to
  the public execution middleware, proving the post-dispatch request has no tools.
- Source inspection found native tool search defers recall and MCP schemas before
  this plugin's allowlist runs. The profile now disables tool search. Correction,
  long-history and summary scenarios passed again with that configuration.
- Summary tests added failure cooldown, prefix fencing, reset invalidation and
  stale-reader admission checks. No failed generation replaces prior recall.
- A saturated-pool evaluation without gateway session bindings reproduced the
  native synchronous fallback (39.1 seconds). The harness now binds the same
  public session context as the gateway. With the admission middleware active,
  the real-model test verified a rejected tool result and zero new worker calls.
  The guard checks capacity and routing before native dispatch and leaves
  status/steer/stop available. Unit tests cover failed probes and concurrent admission.

## Verification and remaining acceptance

The Nix package runs 23 offline contract tests against the pinned Hermes Python
environment. They cover request formats, successful versus rejected dispatch,
subsequent messages, scope, worker grants, retained tool pairs and attachments,
summary failures, concurrent stale writes, reset and persisted recall. Ruff and
Nix formatting also pass. Nix evaluation confirms roommates still uses Luna low,
an empty plugin allowlist and the built-in compressor.

Live Photon/Telegram transport, production CUA tools, restart recovery and provider
outages are not validated by these smoke runs. Native dispatch can still execute
inline after an unexpected scheduling failure or a capacity race with callers
outside the guard. Middleware is not a replacement scheduler and must not be
presented as a universal latency guarantee. Initial admission replies remain slow.

PR #612, created independently during this work, implements an alternative
`messaging_task` lifecycle. It overlaps the same profile and prompt. This plugin
currently targets native `delegate_task`; reconcile those contracts before
combining the PRs. Nothing here changes or closes #612.

After an approved deployment, validate delivery using the real conversation:
start a read-only investigation, ask an unrelated question during it, revise or
cancel, verify the eventual result, and check a roommates TV status request.
Do not start a second gateway against the same account to simulate this test.
