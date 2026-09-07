# Hermes Desktop

## Configuration boundary

`hosts/macbook/hermes-desktop.nix` owns the Mac client package.
`hosts/spark/services/hermes-desktop.nix` scopes the existing Spark backend to
`~/.local/state/hermes/.hermes/profiles/desktop`. It adds no service or plugin.
Keep the existing Spark connection in Desktop; this change needs a Spark deploy,
not another Mac rebuild. Reconnect afterward and start a new Desktop session.

The Desktop profile has its own SOUL, workspace guidance, sessions and memory.
It uses Astra medium with native Astra low delegation available, but no Photon
foreground restriction, automatic conversation snapshot plugin or texting prompt.
Computer tools remain available. Roomcast and its skill are absent. The backend
also stops depending on the Roomcast MCP service. Photon and roommates retain
their current tools and prompts.

The gateway is explicitly pinned to the default profile so changing Desktop's
sticky profile selection cannot retarget messaging on restart. Profiles remain
selectable in the UI: deliberately selecting another profile uses that profile's
tools and persona. This is configuration separation, not a security sandbox.

Codex credentials use Hermes's native root-profile fallback; no OAuth grants are
copied. The backend receives its existing dashboard secret through systemd so the
saved Spark connection retains its authentication. Old conversations and memory
remain in their original profiles; they are not moved into Desktop. Resume them
there when needed, or start new work in Desktop for the clean context.

Nix owns the profile config and prompts. Appearance and saved connections remain
mutable Mac user state. Updating the default model in Nix does not reset a model
override selected for an existing session. Repo discovery is limited to Spark's
`/home/rathi/Documents/Git`; tools execute on Spark even though the UI is on Mac.

## Recommended workflow

Use ordinary **Sessions**, grouped by project, for coding and research. Separate
tabs or windows suit independent jobs. Use **Bots** only for persistent roles:
each bot is a real profile with an ongoing canonical conversation, not a temporary
worker. Bot Chat has its own native messaging protocol; `/new` compacts that chat
rather than making an ordinary fresh session. Routines are scheduled jobs; none
are created by this setup.

Keep the current appearance. Useful controls to try:

- Technical tool view for inspecting actual tool activity.
- Collapsed reasoning for less scrolling, with details available on demand.
- The context meter's breakdown to inspect prompt, skill and tool overhead.
- Status-bar model, workspace, turn time, tokens/sec and cache statistics.
- The Agents pane for worker trees, progress and touched files. It is an
  observability view, not direct control of workers in the separate gateway.
- Git review for inspecting changes. Its built-in Create PR action uses `gh`;
  ask Hermes to use `tea` for this Forgejo repo instead.

Theme, tool presentation and density mostly live in renderer localStorage. Nix
should not write Electron's storage database. UI scale and translucency are taste
choices; leave them as they are while establishing the workflow. Native config
also supports `terminal.font_family` and `display.resume_last_session` if a
specific preference later needs to be declared.

## Research basis

Reviewed upstream revision `693641aa8b4359c602283bdbbc14041e03bc47bc` and official
docs on 2026-09-07. These are source-based recommendations, not latency benchmarks
or a GUI acceptance test.

- [Desktop guide](https://github.com/NousResearch/hermes-agent/blob/693641aa8b4359c602283bdbbc14041e03bc47bc/website/docs/user-guide/desktop.md): sessions, appearance and review workflow.
- [Bot Mode](https://hermes-agent.nousresearch.com/docs/user-guide/bot-mode): persistent profiles, canonical chats and routines.
- [Agents pane](https://github.com/NousResearch/hermes-agent/blob/693641aa8b4359c602283bdbbc14041e03bc47bc/apps/desktop/src/app/agents/index.tsx): worker observability.
- [Profile API](https://github.com/NousResearch/hermes-agent/blob/693641aa8b4359c602283bdbbc14041e03bc47bc/hermes_cli/web_routers/profiles.py): current versus sticky profile.
- [Auth implementation](https://github.com/NousResearch/hermes-agent/blob/693641aa8b4359c602283bdbbc14041e03bc47bc/hermes_cli/auth.py): shared root credential fallback.
