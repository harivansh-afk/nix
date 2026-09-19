# Devin CLI

Shared user defaults live in `dots/devin/config.json`. Activation copies them to
`~/.config/devin/config.json`, backing up local divergence. The configuration
applies to both workstations; use the normal host rebuild after merging.

The default model is `gpt-6-astra-medium`, matching our Codex reasoning setting.
An explicit variant avoids relying on a family alias's remembered selection.
Existing sessions retain their saved model unless changed with `/model` or
`devin --model gpt-6-astra-medium --resume <session-id>`.

## Codex preset

`agent.codex_tools = true` enables shell-based reads/searches and a grammar-based
`apply_patch` tool for GPT models. It shipped in Devin 3000.10.21; Astra command
batching improved in 3000.10.27. Both are included in the tested 3000.10.31.
[Stable changelog](https://docs.devin.ai/cli/changelog/stable).

On 2026-09-19, controlled request captures with imports and subagents disabled
confirmed that this switch also selects a different system prompt: 18,448 to
14,416 bytes and 23 to 14 tools. Those counts describe the experiment, not every
normal session. The enabled prompt includes permission persistence, concise
communication, mid-task steering and targeted validation guidance. This proves
a preset change, not a measured improvement in every task.

This remains Devin's runtime and UI. Its `exec` takes shell-command JSON; Codex's
Astra setup uses JavaScript orchestration. Do not describe the preset as the full
Codex harness.

## Other knobs

Change one behavior at a time after trying the preset in a fresh session:

| Setting | Use | Current choice |
| --- | --- | --- |
| `agent.model` | Select an explicit model and reasoning variant | Astra medium |
| `agent.codex_tools` | Select the GPT prompt/tool preset | Enabled |
| `read_config_from` | Control imported instructions, skills and MCP configuration | Keep existing imports; disabling Claude also removes its integrations |
| `subagents_enabled` | Control delegation availability | Keep upstream default |
| `disabled_tools` | Remove named tools | No additional exclusions |
| `agent.compaction_threshold_tokens` | Compact earlier | Keep upstream default until long-session evidence justifies tuning |

The existing permission mode and shared instructions remain in place. Do not add
a second large Codex prompt on top of the preset. Inspect effective rules with
`devin rules list` before changing imports. User model/preset settings belong in
the user config, not project `.devin/config.json`.
[Configuration](https://docs.devin.ai/cli/reference/configuration/config-file),
[imports](https://docs.devin.ai/cli/reference/configuration/read-config-from).

Evaluate discussion without unwanted implementation, corrections mid-task, a
small edit with targeted validation, and context retention after compaction.
Record the version, concrete model, preset and imported rules with any failure.
