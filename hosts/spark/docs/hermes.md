# Hermes on Spark

`hosts/spark/services/hermes.nix` owns the messaging gateway, desktop backend, model, tool selection
and pinned runtimes. The Hermes flake input tracks an exact upstream revision;
Astra uses the existing Codex OAuth identity with medium reasoning. Activation
clears the old main-model localhost URL while retaining the separate Spark model.

The two processes serve different clients: `hermes gateway` handles Photon
iMessage; `hermes serve` exposes the authenticated tailnet API used by the Mac
desktop app. They share Hermes state. The backend does not serve the web dashboard.

The full native toolset is available in CLI and Photon sessions: terminal/files,
browser, computer use, delegation, skills, memory and conversation recall. The
local knowledge-base plugin adds read-only retrieval. Cua's version-matched skill
pack is linked separately. There are no custom hooks or scheduled jobs.

## Learning from work

The Nix-owned `self-evolve` skill routes verified lessons through PRs to
https://git.harivan.sh/harivansh-afk/nix. Add or edit
`dots/hermes/skills/<name>/SKILL.md`; Nix discovers these directories and links
them into Hermes Home on deployment. No per-skill module edit is needed.
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

The services run as Hari with his home, user D-Bus and Sway display. Startup waits
for the active Wayland socket and reads the user manager's display environment;
no display number is hard-coded. If you restart Sway independently, restart both
Hermes services afterwards so they reconnect to the new display. Cua uses the
native Wayland backend; XWayland stays disabled. Desktop actions share the visible
VNC session, so concurrent workers must coordinate native GUI actions.

Chromium's original profile stays at `~/.config/chromium/Default`, using GNOME
Keyring. Nix declares Chromium, accessibility, the Sway-specific default-browser
association and Hermes's profile selection. Cookies, passwords and profile files
are private mutable state, never Nix store contents or Git assets.

Hermes snapshots that profile into its own private browser state at each fresh
browser session and drives a visible window. Existing logins are copied, but
extensions and some storage (including IndexedDB) are not. Log in through the
original browser when refreshing the source identity. Changes inside a snapshot
are not a backup of the original profile. Named browser sessions support parallel
work without reusing a single automation tab.

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

Update `hermes-agent` with `nix flake update hermes-agent`. Browser Use has a
separate uv2nix environment: update its pyproject constraint and run
`uv lock --project pkgs/browser-use`. Cua's binary and skill archive share a
release version and fixed hashes. Rebuild through the normal PR/deployment flow.

`nix build .#checks.aarch64-linux.hermes-runtime` tests packaged startup and Photon
module resolution without credentials or network access. Before calling a
new deployment operational:

1. Check both Hermes services and their journals; confirm Photon connected and
   retained the sender allowlist. An expired Photon account needs reauthentication.
2. Run `hermes computer-use doctor` in Spark's Sway session. Verify accessibility,
   capture and a harmless action in a scratch application.
3. Ask for a harmless authenticated browser read; confirm the expected account
   and return a screenshot. Test steering and cancellation during a task.
4. Text the existing Photon line from Hari's phone, have it perform a harmless
   task, and check its reply and attachment. No outbound test is automatic.
5. Restart the services and repeat a request to verify persistence.

The PR does not activate the system or send iMessages. The restored secret requires
Spark's host age identity (root activation) or the Mac's admin identity to decrypt;
its current remote account validity must be checked at deployment.
