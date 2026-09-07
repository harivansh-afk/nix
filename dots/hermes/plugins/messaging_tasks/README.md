# Messaging tasks

A Photon-only tool plugin using stock Hermes. Nix installs it through
`services.hermes-agent.extraPlugins`; `plugins.entries.messaging-tasks` grants
completion injection and sets the active-task limit. No hooks or source patches.

`messaging_task` supports start, status, cancel and continue. Launch uses
`ctx.subagent_lifecycle`, which schedules worker execution asynchronously rather
than using `delegate_task`'s synchronous fallback. A full admission budget returns
an error before launch. The budget covers this plugin instance, not other Hermes
work. Workers inherit the configured model/reasoning and existing tool restrictions;
the explicit toolsets keep this plugin out of their tools.

A host-supervised watcher saves the result in `ctx.state` before requesting a new
turn through `ctx.inject_message`. The originating route comes from Hermes's
session context, never model arguments. Native handles stay in private plugin
state. Status and continuation require the originating session ID. A notification
marked `accepted` means queued by the gateway, not delivered to the user. Rejected
notifications retain the result for a later status request; there is no automatic
retry that could send duplicate messages.

Workers receive the short `worker.md` contract. Reports distinguish completion,
missing input, blockers and uncertainty. Invalid reports remain uncertain and
retain the raw response. A continuation passes the prior assignment, report and
new input to a fresh worker. It does not resume the original transcript. Each
predecessor can have one continuation; active or uncertain work is not restarted.
Cancellation is cooperative and cannot reverse effects. There is no live steering
API here: corrections require cancellation followed by a continuation after stop.

State holds at most 128 indexed tasks, pruning finished records first. Questions,
blockers and uncertain outcomes remain until resolved. Process/plugin replacement
marks previously active records uncertain on the next admission; it never replays
them. This is retained task context, not durable execution across restarts.

## Review and deferred acceptance

This is a draft. Only static checks are authorized for this iteration. The isolated
contract tests are provided but have not been run. Before enabling in production,
exercise the real plugin loader, profile routing and production models with:

- A slow worker plus an unrelated message; no synchronous fallback or polling.
- Full capacity and simultaneous starts; rejected work must not execute.
- Two conversations; no cross-session status, cancellation or result delivery.
- Cancellation during a tool call, a missed correction, and a worker question
  answered after unrelated chat; no duplicate external effects.
- Admission/state-write failure, malformed output, gateway rejection, plugin unload
  and process restart; no fabricated completion or automatic replay.

Known limits: foreground yielding is still prompt-driven, and native
`delegate_task` remains available for CLI compatibility. Hermes's public lifecycle
service creates the child synchronously before scheduling its work; admission may
therefore still spend time loading tools. Completion injection has no delivery
receipt. There is no provider-wide priority reservation, dynamic context engine,
summary injection, or latency claim.

Dependencies are the documented PluginContext services, public subagent request
and result types, and the exported session-context/delegated-child predicates.
No live AIAgent fields, private worker registries or gateway objects are accessed.
