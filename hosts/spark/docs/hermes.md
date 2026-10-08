# Hermes on Spark

`hosts/spark/services/hermes/default.nix` owns the messaging gateway, desktop backend, model, tool selection
and pinned runtimes. The Hermes flake input tracks an exact upstream revision.
The Relay personal assistant uses Opus 5.5 through Hermes's native Anthropic transport and the existing
Claude Code subscription login. Desktop uses Astra through the authenticated
Devin loopback adapter declared in `hermes/devin.nix`.

The two processes serve different clients: `hermes gateway` handles Relay and Telegram;
`hermes serve` exposes the authenticated tailnet API used by the Mac
desktop app. Desktop starts in its own `desktop` profile; Relay uses the existing
`imessage` profile and Telegram uses `roommates`. The backend does not serve the
web dashboard. See [Desktop setup and features](hermes-desktop.md) for the state
boundary and recommended workflow.

The Desktop profile also exposes the [Robinhood MCP](robinhood.md).
The personal assistant has no Robinhood integration.

## Devin inference

`hermes-devin.service` runs the pinned `devin-codex serve --compatibility` on
`127.0.0.1:19476`. It reads the existing Devin CLI login at
`~/.local/share/devin/credentials.toml`; sign in with Devin before starting it.
The service creates a private token under `/var/lib/hermes-devin` on first start
and retains it across restarts. Hermes's per-profile command secret source loads
the token for the default, Desktop and roommates profiles. Credentials never enter
the Nix store. The Desktop backend waits for the adapter's authenticated health
check. The messaging gateway starts independently of Devin; its Telegram roommate
profile still uses Devin for inference, while Relay uses Claude.
After renewing the Devin login, restart `hermes-devin` and the affected clients
to reload credentials. Relay does not need a restart for a Devin login change.

Desktop defaults to `devin` / `gpt-6-astra` with medium reasoning; its delegated workers
use Astra low. The roommates profile uses Devin `gpt-6-sol` with low reasoning.
The personal assistant and its workers use `anthropic` / `claude-opus-5-5`, with medium reasoning
for conversation and low for workers. Its separate `.env`, containing only Relay credentials, prevents the shared
Anthropic API key from taking precedence over the Claude Code subscription credentials.
The Devin command secret source is disabled in this profile. OAuth credentials and
refresh state remain in Claude Code's private runtime store, outside Nix and Git.

Switch a Desktop session with:

```text
/model gpt-6-astra --provider devin
/model gpt-6-astra --provider openai-codex
```

The adapter loads its account-available model catalog through the installed Devin CLI at startup.
The service allows writes to the CLI's log directory, which even `devin models list`
requires; the rest of the home directory remains read-only.
Responses are
buffered and model tool calls are serial. Inline image input is supported. Start a
fresh session when moving between Codex and Devin: old native Codex reasoning
was issued by a different backend. New defaults apply after rebuilding Spark;
existing sessions can retain their saved model selection.

## Mac Desktop

`hosts/macbook/hermes-desktop.nix` installs `/Applications/Hermes.app` from the
upstream `minimal.hermesDesktop` Nix package and exposes `hermes-desktop` on PATH.
Desktop and Spark use the same `hermes-agent` flake input. The app's install stamp
records that input's revision; upstream's Desktop version can remain unchanged
across many commits. Existing Desktop preferences and saved connections remain
in their current user-data directory.

Update the `hermes-agent` flake input through a Nix PR. After merging, pull the
repo on the Mac and run `just switch`, then quit and reopen Hermes. A Spark
deployment alone does not update the Mac app. Use Nix rebuilds to update these
installations rather than Desktop's updater.

Select the existing Spark connection in Desktop's Settings → Gateways to keep
using Spark's sessions, models and tools. Rebuilding the app does not change its
saved connection or grant control over another process's active workers.

## Messaging behavior

`hosts/spark/services/hermes/personal.nix` owns the personal assistant profile;
`relay.nix` pins the upstream Relay-Hermes plugin and installs its encrypted
credentials. The profile keeps its historical `imessage` directory so memories,
conversation history, skills and OAuth grants stay in place. This directory name
does not enable iMessage. The gateway routes `relayapp` to `imessage` and Telegram
to `roommates`; Photon is removed.

The root/default profile loads the platform plugin but has no Relay credentials,
CLI tools, MCP connections, persona or memory. Only the personal profile's `.env`
contains the Relay token and owner allowlist. Desktop and roommates have separate
credential scopes.
On the first gateway start, with the old gateway stopped, its pre-start migration
backs up the root SQLite database, preserves session IDs and messages, and
changes default routing to `imessage`. It moves memories, session files, cron
state, pending messages, platform state and local skills into the profile.
Legacy `sessions.json` is archived so the old namespace cannot be reimported.
The backend starts after the gateway; migration refuses an open root database.
Backups live in `~/.local/state/hermes/imessage-migration-backup`. Subsequent
starts skip the completed migration.

Deploy while agents are idle and no CLI/Desktop session is using `default`.
After deployment, verify Relay can recall the existing profile memories and
conversation history, and check Telegram independently. A Relay chat has its own
transport session; the previous Photon thread is retained for recall, not rewritten
into a Relay conversation. Existing active workers are not
migrated between running processes. Shared OAuth grants are not copied.

Desktop's empty SOUL is intentional; the UI may report that it is empty. Select
`desktop` for work, `imessage` for the personal assistant and `roommates` for TV.

Automatic busy acknowledgements stay disabled; messaging updates are agent-written
responses. Relay uses stock Hermes tools, automatic tool discovery and native
delegation. There is no custom request middleware, foreground tool allowlist or
worker conversation-copying layer. Opus 5.5 medium handles conversation and Opus
5.5 low handles delegated work. The roommates profile uses Sol low and no plugins.
Profiles can run concurrently but share gateway restarts. Roomcast's shared HTTP
MCP service is independent of those restarts; see [roomcast.md](roomcast.md).

CLI and Relay sessions have terminal/files, delegation, skills, memory and
conversation recall, plus agent-browser CLI for browser pages and direct
Cua MCP for native windows. Hermes's native browser and computer-use toolsets are disabled. The personal
KB and its search plugin are disabled; conversation memory remains enabled.
The `spark-computer` skill and
Cua's version-matched skill pack are supplied by Nix. There are no custom
hooks or scheduled jobs.

`skillSources` in `hermes/default.nix` selects the upstream skills and includes
`dots/hermes/skills/`. Hermes reads the resulting store directory through
`skills.external_dirs`; bundled seeding and project discovery are disabled.
The first activation archives the old skill tree at
`~/.local/state/hermes/skills-before-nix`. The store tree uses real directories
because upstream's bundle-sync scanner does not follow directory symlinks.

## Learning from work

The Nix-owned `self-evolve` skill routes verified lessons through PRs to
https://git.harivan.sh/harivansh-afk/nix. Add or edit
`dots/hermes/skills/<name>/SKILL.md`; Nix includes these directories in the store
skill tree on deployment. No per-skill module edit is needed.
Supporting scripts and references live alongside SKILL.md. Agent guidance
requires this path for skills, plugins, configuration and durable behavioral
instructions. Private memory, conversations, credentials and browser state stay
outside Git. This is instruction-based governance, not a filesystem sandbox.

The native skill-creation nudge is disabled so it does not request direct runtime
skill writes; the task/correction trigger in AGENTS.md points to self-evolve.
Hermes completes and validates the PR, presents its link and checks, then merges
routine skill-only changes after green checks unless Hari requests review first.
Broader changes require scoped authorization or explicit yes/no identifying the
PR. Changes after approval must be rechecked and material changes reapproved.
Merge, deployment and runtime proof are reported separately.

Relay supports native buttons and multi-select cards through the upstream plugin.
When a PR needs approval, share its link and identify the exact PR and head in the
choices. Recheck the head and CI before merging; an unanswered request leaves the
PR open. The plugin does not override Hermes's `send_clarify`, so native `clarify`
uses Hermes's text-choice fallback. Card rendering and response delivery need a
real Relay acceptance check.

This adds no service, hook, schedule, model provider or account integration. It
does not install Nous' separate DSPy/GEPA Self-Evolution research optimizer. Skill
files stay on Spark; reasoning uses the configured inference provider.

## Desktop and browser

Hermes uses agent-browser CLI and upstream Cua (`computer`) MCP.
Chromium starts only for browser tasks; native calls attach to the existing Cua
user service. Load the
[spark-computer skill](../../../dots/agents/skills/spark-computer/SKILL.md) for
exact upstream tool names, ownership, serialized input and cleanup.

The Devin adapter accepts inline images, including screenshots returned by tools.
Image consumption is verified through Sol and Astra in Codex; Hermes's own MCP
image handling still needs a separate acceptance check. Existing Codex processes
must be restarted to load the image-capable model catalog. Hermes uses the
unmodified upstream package.
For service ownership, image-coordinate handling, diagnosis and validation results,
see [Spark browser and desktop](browser.md).

## Relay

Relay is a separate messaging app, not an iMessage bridge or a replacement model.
Hermes still runs Opus 5.5 on Spark. Compared with Photon, the upstream Relay
plugin provides swipe-reply context, reactions, typing indicators, rich cards,
attachments, and a durable SQLite inbox with acknowledged WebSocket events and
idempotent sends. This improves transport recovery and presentation; model/tool
latency is unchanged. Edits and unsend are not supported.

The existing account's Agent Token and single-contact allowlist are restored from
Git history as `secrets/hosts/spark/hermes-relay.env`. The token successfully read
the Relay chats API on 2026-10-08. At activation, only this secret is installed to
`profiles/imessage/.env`; it is excluded from the root and Desktop environment.
Unknown contacts must not be able to start work. Keep the allowlist populated when
rotating the token. Credentials and contact IDs remain encrypted in Git.

The plugin uses an outbound WebSocket to `https://api.relayapp.im` and HTTPS sends;
there is no public listener, Mac relay, Node sidecar or Photon control port.
Its state remains in `profiles/imessage/relay`. The existing inbox is bound to the
same account token; preserve it across restarts. Changing the token requires
following upstream's state-binding procedure rather than deleting the inbox.
The 2026-10-08 inspection found one unfinished event from September in that inbox.
The PR preserves it; the adapter may replay it on first startup. This is the
remaining state from the earlier deployment's busy-follow-up bug, not a new message.
Quiet display settings suppress streaming previews, tool progress and automatic
busy acknowledgements.

The former Photon secret, adapter environment, route and sidecar build are removed.
Existing Photon history remains private on disk. Existing scheduled jobs addressed
to Photon require an explicit delivery-target update before reuse.

Group TV requests still use the separate [roommate agent](roomcast.md#roommate-agent)
on Telegram, with separate tools and state.

## Updating and acceptance

Update `hermes-agent` with `nix flake update hermes-agent`. The shared computer
package pins agent-browser's binary and skills. Cua's binary and skill archive share a release
version and fixed hashes. Rebuild through the normal PR/deployment flow.

`nix build .#checks.aarch64-linux.hermes-runtime` tests packaged startup, Relay
plugin discovery, profile routing and credential isolation with fixture credentials
and no network access. Before calling a
new deployment operational:

1. Check both Hermes services and their journals; confirm Relay received its
   WebSocket ready frame and retained the owner allowlist. Check that Photon is absent.
2. Use Cua's `list_windows` and inspect a scratch application's state.
   Verify a harmless action and an actual screenshot in Astra's context.
3. In a distinct named session, ask for a harmless authenticated browser read;
   confirm the expected account and return an agent-browser screenshot.
   Test steering and cancellation during a task, then close both sessions and
   verify the task's browser tab closed while pre-existing tabs remain.
4. Message the existing agent in Relay from Hari's phone, have it perform a harmless
   task, and check its reply, attachment, swipe-reply context and rapid follow-up.
   No outbound test is automatic.
5. Restart the services and repeat a request to verify persistence.

Opening the PR does not activate Relay or send messages. Merge and deployment are
separate from the phone acceptance checks above. The encrypted secret uses Spark's
host age identity at activation; the Mac's admin identity can also decrypt it.
