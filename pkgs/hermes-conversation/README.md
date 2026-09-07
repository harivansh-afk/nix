# Photon conversation policy

Nix installs this plugin through upstream Hermes's `extraPlugins`. One
`llm_request` middleware limits the tools offered to Photon: delegation, recall,
preferences, skills, clarification and quick TV controls. Native workers retain
their execution tools. CLI, subagents and the roommates profile are unaffected.

After a confirmed native background dispatch in the current turn, the next
request uses `tool_choice=none` so the model can finish its reply. The allowed
schemas stay present. A new user message restores normal tool choice. This is
request policy, not an execution sandbox or a custom agent loop.

The personal conversation uses Astra medium; native workers use Astra low.
Prompts live in `dots/hermes/`. The plugin owns no worker state or scheduler:
Hermes handles delegation, steering, cancellation and completion delivery.

Admission guarding, context selection, summaries, tests and model evaluations
are a separate follow-up. Native synchronous fallback remains possible, including
at capacity. The middleware requests a final reply; it does not enforce a wall-clock
deadline or guarantee that a provider obeys tool choice. No latency improvement or
live messaging acceptance is claimed for this split.
