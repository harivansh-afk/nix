# Hermes conversation plugin

Nix installs this package with upstream `extraPlugins`. `plugins.enabled` opts in;
`context.engine = "conversation"` selects its context engine. There are no Hermes
patches, hooks, additional services or dependencies. The flake's Hermes pin owns
the plugin API version and Python runtime; the package build runs its contract tests.

## Runtime boundaries

- Photon requests expose the configured conversation tools. Workers retain the
  parent's authorized execution tools. `tools.tool_search.enabled = "off"` is
  required in this profile: otherwise upstream defers recall/MCP schemas before
  request middleware sees them. The plugin filters provider requests, not tool
  permissions, and upstream middleware failures are fail-open.
- After an actual `delegate_task` result with `status: dispatched`, the next model
  request has no tools. The model writes the handoff reply and ends the turn.
  Rejections, corrections and status checks do not trigger that rule. The next
  user turn restores the selected tools. No static acknowledgement is generated.
- A tool-execution middleware serializes Photon admission checks and rejects a
  full native pool or missing completion route before dispatch. Probe failures
  reject work too. Status, steering and cancellation bypass admission. This avoids
  the native synchronous fallback for these checked conditions; it does not replace
  the scheduler. Calls outside this middleware can race it, and unexpected native
  dispatch failures can still fall back inline. Keep all Photon launches on this
  path and rerun the capacity evaluation when upgrading Hermes.
- Hermes owns dispatch, steering, cancellation and completion delivery.
  The context engine reads its session-owned active-task snapshot; it does not
  create a second task ledger. The native pool is process-local and counts call
  slots; a batch can have multiple children. The guard conservatively counts live
  completion units, not provider-wide requests. There is no added durable queue, crash resumption,
  exactly-once execution or cross-task resource locking.
- Photon sends a recent dialogue view plus derived recall and current task state.
  System/developer instructions and the complete latest turn, including images and
  tool pairs, are retained. `input_tokens` is an estimated selection budget, not a
  strict provider limit: tools and oversized latest input can exceed it. Ordinary
  selection leaves Hermes history intact; an explicit/overflow compression request
  uses the same reduced view. This does not bound Hermes's in-memory transcript.
- Summary work runs after completed turns, on one daemon thread per plugin
  instance, through `ctx.llm` and the `conversation_summary` auxiliary route.
  It never joins the foreground turn. A profile-local SQLite cache has a
  cross-process lease, timeout, retry cooldown and prefix validation. Revised or
  reset history fences stale results. Failed summaries preserve prior recall;
  missing history is retrieved with `session_search`. Raw tool outputs are omitted
  from summaries, so workers must return concrete evidence in their final response.
- CLI and subagents retain full-history selection and inherited
  `ContextCompressor` defaults. Upstream's host-level compression settings do not
  configure external engines; add explicit plugin support before relying on new
  compression knobs in this profile. The roommates profile explicitly disables
  plugins and selects upstream `compressor`, retaining Luna low and its TV tools.

Configuration and prompts live in `hosts/spark/services/hermes.nix` and
`dots/hermes/`. Plugin updates participate in the gateway/backend restart triggers.
Turning the plugin off also requires restoring `context.engine = "compressor"`;
tool search can then return to upstream defaults. Conversations and the summary
cache remain mutable private state outside Git and the store.

## Evaluation

`evaluate.py` runs actual Hermes `AIAgent` turns and native background delegation
with the Nix-selected production models. It replaces external tools with a
read-only coursework fixture and uses a separate Hermes home. It never starts a
gateway, sends messages or connects to production MCP servers. Completion events
are collected from Hermes and explicitly supplied to the conversation; adapter
routing and live delivery require separate post-deployment acceptance.

Evaluate settings from the worktree, then use the Python environment exported by
the matching Hermes package. Python is invoked through `uv`:

```sh
nix eval --json .#nixosConfigurations.spark.config.services.hermes-agent.settings > /tmp/hermes-settings.json
PYTHONPATH=pkgs/hermes-conversation uv run --no-project --python "$hermes_python" \
  pkgs/hermes-conversation/evaluate.py \
  --settings /tmp/hermes-settings.json \
  --auth "$HOME/.local/state/hermes/.hermes/auth.json" \
  --output /tmp/hermes-eval-correction --scenario correction
```

`hermes_python` is the `bin/python3` in `services.hermes-agent.package.hermesVenv`.
Each output directory must be new and outside the checkout. The harness copies
the OAuth file with mode 0600 and removes its copy on normal/error exit. Hard
process termination can leave it behind; evaluation directories are private and
should be removed after inspection. No credentials enter reports. Reports include
model request metadata, source/config hashes, durations, fixture effects and
responses. They are private local artifacts, not files to commit.

Scenarios cover greeting, full-capacity rejection, delegation with a concurrent unrelated question,
in-flight scope correction, long-history selection and background summary recall.
`--baseline` uses the built-in compressor without the plugin (except for the
plugin-specific summary scenario). Automated assertions supplement response and
trace review; they are smoke evaluations, not a general capability score.

Offline checks: `nix build .#checks.aarch64-linux.hermes-conversation --no-link`.
See [measured results](../../hosts/spark/docs/hermes-conversation-evaluation.md).
