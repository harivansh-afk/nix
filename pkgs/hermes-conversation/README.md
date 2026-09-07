# Photon conversation context (draft)

This follow-up is stacked on #613's conversation prompt and request policy.
It adds a context engine, background summaries and admission checks through
upstream Hermes plugin APIs. Native Hermes still owns the worker lifecycle.
The parent-to-worker text snapshots from #613 remain enabled; this draft
changes the parent context from which those snapshots are captured.

The engine selects recent conversation turns while retaining tool pairs and
attachments. Its input budget is an estimate; the newest turn remains intact
when oversized. It projects active native tasks and adds derived recall from a
private SQLite store. Astra low generates summaries outside the foreground;
leases, prefix checks and conditional writes fence stale results. Other platforms
and delegated children retain native compression. Roommates explicitly selects
the native compressor and has no enabled plugins.

Execution middleware checks Photon background capacity and completion routing
before spawning. The configured limit is two workers. Status, steering and stop
remain available. Request policy retains #613's allowed schemas and requests
`tool_choice=none` after confirmed dispatch.

## Draft review boundaries

This is preserved implementation work, not ready for deployment:

- Context selection can omit dialogue newer than a lagging summary but older than
  the recent window. Coverage must be preserved or the gap surfaced before merge.
- Recall and task state are refreshed per request, not frozen for a turn; the
  effect on consistency and prompt caching needs evaluation.
- The token budget reserves a fixed allowance rather than measuring all tool,
  recall and task content. It is not a hard context or memory bound.
- Admission checks are serialized only among this plugin's callers. They are not
  atomic with native scheduling, and scheduling failures can still fall back inline.

The first PR is independently usable without these additions. Resolve the above
and evaluate the combined behavior before promoting this draft.

## Validation

`tests/test_conversation.py` contains offline contract tests against pinned Hermes.
The Nix package runs these during its build; the aarch64 flake check includes it.
`evaluate.py` is an explicit production-model fixture harness, separate from CI.
It uses an isolated Hermes home and does not test live transport or production
MCPs. No model or live messaging tests were run during this split.

[Earlier evaluation results](../../hosts/spark/docs/hermes-conversation-evaluation.md)
are historical, not validation of this draft. #613 contains the source references
and rationale for the conversation prompt. Both PRs keep Astra medium for
conversation and Astra low for native workers; this draft adds Astra low summaries.
