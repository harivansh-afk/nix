# Hermes on Spark

`hosts/spark/services/hermes.nix` owns the messaging gateway, desktop backend, model, tool selection
and pinned runtimes. The Hermes flake input tracks an exact upstream revision;
Astra uses the existing Codex OAuth identity with medium reasoning. Activation
clears the old main-model localhost URL while retaining the separate Spark model.

The two processes serve different clients: `hermes gateway` handles Photon
iMessage; `hermes serve` exposes the authenticated tailnet API used by the Mac
desktop app. They share Hermes state. The backend does not serve the web dashboard.

CLI and Photon sessions have terminal/files, delegation, skills, memory and
conversation recall, plus the shared `computer` MCP server for browser and desktop
work. Hermes's native browser and computer-use toolsets are disabled. The local
knowledge-base plugin adds read-only retrieval. The `spark-computer` skill and
Cua's version-matched skill pack cover the shared MCP workflow and native desktop
driver respectively. There are no custom
hooks or scheduled jobs.

## Skill inventory

`hermes.nix` builds the selected skills into a store directory and sets
`skills.external_dirs` to that directory. `upstreamSkills` explicitly selects
upstream skills from the pinned Hermes source; initially only `hermes-agent`,
which upstream requires. The directory also contains `spark-computer`,
`cua-driver`, and every skill under `dots/hermes/skills/`. Project skill discovery
is disabled so changing the working directory does not expand this inventory.
The build copies these sources into real directories: upstream's bundle-sync
scanner uses `Path.rglob`, which does not follow directory symlinks.

Nix writes `.no-bundled-skills` to opt out of upstream bundle seeding. Hermes
recognizes the externally supplied `hermes-agent` and does not copy it locally.
On activation, `hermes-skills.sh` moves runtime skill directories and symlinks
out of discovery into private `~/.local/state/hermes/skills-backups/migration.*`
directories. It preserves runtime metadata files and leaves memory, conversations,
credentials and browser state alone. Repeated activation with no runtime skills
creates no backup. New runtime skills are archived on the next activation;
this is declarative reconciliation, not a sandbox against terminal writes.

## Learning from work

The Nix-owned `self-evolve` skill routes verified lessons through PRs to
https://git.harivan.sh/harivansh-afk/nix. Add or edit
`dots/hermes/skills/<name>/SKILL.md`; Nix discovers these directories and includes
them in the store skill directory on deployment. No per-skill module edit is needed.
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

The installed Photon adapter's `send_clarify` renders choices as
[native iMessage polls](https://photon.codes/docs/spectrum-ts/content/polls).
Hermes shares the PR link and uses `clarify` for Merge / Keep open choices when
approval is needed. Each choice identifies the PR and head, because upstream
turns a selected `poll_option` into choice text for the pending clarification;
it does not bind that vote to a Forgejo transaction. Recheck the head and CI
before merging. Expiry or failure leaves the PR open with its review link.

This uses the existing adapter and sidecar, not a mini-app or custom callback
service. Upstream falls back to a text list if sending the poll fails; native
rendering and vote delivery still need an actual iMessage acceptance check.

This adds no service, hook, schedule, model provider or account integration. It
does not install Nous' separate DSPy/GEPA Self-Evolution research optimizer. Skill
files stay on Spark; reasoning still uses the configured Astra Codex provider.

## Desktop and browser

Hermes uses the shared `computer` MCP server, connecting to the existing browser
and CUA daemon without waiting for a display at gateway startup. Load the
[spark-computer skill](../../../dots/agents/skills/spark-computer/SKILL.md) for
browser/native actions, named sessions and cleanup. Tool names are
`mcp__computer__computer_exec` and `mcp__computer__computer_close`.

Use the normal `vision_analyze` tool to load each returned MCP `MEDIA:` path
into Astra's image context. Hermes uses the unmodified upstream package.
For service ownership, image-coordinate handling, diagnosis and validation results,
see [Spark browser and desktop](browser.md).

## iMessage

Photon's encrypted environment is restored from the former deployment. sops-nix
writes it at activation; upstream Hermes merges it into its private `.env`. The
entire Node sidecar and its locked dependencies are built in Nix, including helper
modules omitted by upstream's writable-mirror fallback at the pinned revision.
Photon binds its control endpoint to loopback port 18789.

The existing `PHOTON_ALLOWED_USERS` should identify Hari. Verify that allowlist and
credentials after activation; unknown senders must not be able to start work.
Photon is a managed iMessage bridge, requiring no Mac relay or public webhook.
Inbound attachments may supply only metadata; text requests and outbound files
and screenshots are the supported baseline.

## Updating and acceptance

Update `hermes-agent` with `nix flake update hermes-agent`. The shared computer
package takes Python and Playwright from nixpkgs. Cua's binary and skill archive share a release
version and fixed hashes. Rebuild through the normal PR/deployment flow.

`nix build .#checks.aarch64-linux.hermes-runtime` tests packaged startup and Photon
module resolution without credentials or network access. Before calling a
new deployment operational:

1. Check both Hermes services and their journals; confirm Photon connected and
   retained the sender allowlist. An expired Photon account needs reauthentication.
2. Start a named computer session with `desktop: true`; use
   `await desktop.list_windows()` and inspect a scratch application's state.
   Verify a harmless action and an actual screenshot in Astra's context.
3. In a distinct named session, ask for a harmless authenticated browser read;
   confirm the expected account and return a screenshot with `display(...)`.
   Test steering and cancellation during a task, then close both sessions and
   verify the task's browser tab closed while pre-existing tabs remain.
4. Text the existing Photon line from Hari's phone, have it perform a harmless
   task, and check its reply and attachment. No outbound test is automatic.
5. Restart the services and repeat a request to verify persistence.

The PR does not activate the system or send iMessages. The restored secret requires
Spark's host age identity (root activation) or the Mac's admin identity to decrypt;
its current remote account validity must be checked at deployment.
