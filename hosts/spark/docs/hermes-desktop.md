# Hermes Desktop

## Configuration boundary

`hosts/macbook/hermes-desktop.nix` owns the Mac client package.
`hosts/spark/services/hermes-desktop.nix` scopes the existing Spark backend to
`~/.local/state/hermes/.hermes/profiles/desktop`. It adds no service or plugin.
Keep the existing Spark connection in Desktop; this change needs a Spark deploy,
not another Mac rebuild. Reconnect afterward, explicitly select **desktop** in
the profile picker, and start a new session. Desktop persists its own profile
selection and can explicitly request `default` even when the server starts in
`desktop`; changing the server home does not rewrite the Mac's selection.

The Desktop profile has its own SOUL, workspace guidance, sessions and memory.
It uses Astra medium with native Astra low delegation available, but no Photon
foreground restriction, automatic conversation snapshot plugin or texting prompt.
Computer tools and native Desktop/project tools remain available. Tool discovery
uses upstream `auto`: less common tools are described on demand instead of always
including their complete schemas. This is not a measured latency improvement.
Roomcast and its skill are absent. The backend
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

### Corrections during work

The profile sets `display.busy_input_mode = steer` for generic busy prompt
submission. Stock Desktop's composer explicitly selects an action, bypassing
that setting:

| Action while busy | Behavior |
| --- | --- |
| `/steer <correction>` | Inject after the next tool boundary without cancelling model generation |
| Enter with plain text | Redirect: cancel current generation and continue with the correction; tools reach a safe boundary |
| Cmd+Enter on Mac | Queue a separate next turn |

Use `/steer` for a correction to ongoing work and Cmd+Enter for an independent
follow-up. A UI action labelled steering can still call redirect. Changing plain
Enter to true steer would require an upstream Desktop feature; this PR does not
patch the client or add a hook. When idle, `/steer` becomes a normal next message.

### Sessions and projects

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
- Branch a conversation at a message to explore another approach. This copies
  chat context, not a filesystem worktree.
- Drag a session into the composer to reference it with `@session`. The agent
  can retrieve it with `session_search`; the entire chat is not injected.
- Create a project worktree for independent code changes, choosing `main` as
  the base. Upstream uses the repo's `.worktrees/<slug>` directory and a
  `hermes/<slug>` branch. Review Last turn before opening the PR.

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
- [Composer submit](https://github.com/NousResearch/hermes-agent/blob/693641aa8b4359c602283bdbbc14041e03bc47bc/apps/desktop/src/app/chat/composer/hooks/use-composer-submit.ts): redirect versus queue.
- [Native slash commands](https://github.com/NousResearch/hermes-agent/blob/693641aa8b4359c602283bdbbc14041e03bc47bc/tui_gateway/methods_tools.py): `/steer` behavior.
- [Connection routing](https://github.com/NousResearch/hermes-agent/blob/693641aa8b4359c602283bdbbc14041e03bc47bc/apps/desktop/electron/connection-config.ts): explicit remote profile selection.

## Acceptance after deployment

The PR's checks load the generated config and SOUL through native Hermes code
in a temporary profile, with a different root prompt and Roomcast config. They
verify isolation, model-independent settings and the credential fallback path.
They do not prove a live OAuth refresh, model behavior or the Mac UI.

After selecting `desktop`, verify the current profile and Astra medium, then
start a fresh session. Inspect its context/tools for the Desktop prompt and
absence of Roomcast. Run a bounded task, send `/steer`, queue a follow-up with
Cmd+Enter, and verify ordered delivery. Finally check Photon and the roommates
chat still use their own prompts and tools. No scheduled work is needed.
