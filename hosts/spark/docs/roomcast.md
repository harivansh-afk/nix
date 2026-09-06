# Roomcast on Spark

The public Roomcast flake owns the application, package and NixOS module. This
repo pins its revision and configures Spark's LAN interface, TV serial, address
hint, discovery scope and Hermes integration. Hermes uses the module's package.

## Roku player

Spark selects the sideloaded Roomcast Player (`dev`) with timestamp seeking and
subtitle control enabled. Install Roomcast Player 1.3.3 or newer before deploying
these settings. The ZIP is built from the pinned Roomcast input with
`nix build --inputs-from . roomcast#roku-player`; upload
`result/roomcast-player.zip` through the TV's developer installer. Installer
credentials stay outside Git and the Nix store.

New movies and episodes request captions on, preferring English, using the
Roomcast module defaults. Availability depends on the source. The `subtitles`
tool reads tracks or changes on/off, language and track selection; its
confirmation reports native player state. Verify visible captions and their
dialogue timing on the TV. Seeking and a timestamp start also need playback
acceptance after deployment; installing the ZIP alone does not enable them in
the running service.

A Roomcast service restart discards the active relay session. Record the title,
episode and position before restarting, then issue a fresh play request with
`start_seconds` to resume. A paused, healthy session uses `control` resume.

## Network

Spark uses DHCP on `wlP9s9`; no router access or reservation is required. The TV's
serial is authoritative. The initial IP is a hint, and its MAC can locate a newer
neighbor-cache entry. SSDP uses a dedicated reply port opened only on the LAN
interface. If multicast is filtered, discovery checks TCP 8060 in the two
configured /24 ranges, with serial verification before any control command.
Those ranges are a bounded search policy, not a promise of discovery on every
network. Broader moves or client isolation can still require operator changes.

A systemd socket bound to the LAN interface exposes only media on TCP 18795,
independent of Spark's current address. Each playback URL uses the kernel-selected
source address for the verified TV. Requests need a session token and the TV's
source IP. Control stays on a group-protected Unix socket. The serial/IP checks
prevent accidental targeting; they are not cryptographic LAN authentication.

## Acceptance

Address recovery from an intentionally stale hint and native YouTube playback
have been verified live. After deployment, verify direct website playback without
the temporary Mac forward. A lease change during an existing stream can still
require a new play request. Pair YouTube using its on-screen TV code before testing
precise seeking; credentials stay in private Roomcast state.

## Roommate agent

`roomcast-mcp.service` serves the existing Roomcast MCP application through the
SDK's Streamable HTTP transport at `http://127.0.0.1:18796/mcp`. The gateway's
personal and roommate profiles and the dashboard share this one process. The
MCP service forwards requests to the single playback service over
`/run/roomcast/control.sock`; restarting Hermes does not restart playback or MCP.
The endpoint accepts local connections from root and the repo owner's UID only.
It has no public route. The MCP service runs as a dynamic user with the Roomcast
socket group and has no home-directory access.

Keep the logical connection names `roomcast` and `roommates_tv` distinct even
though their URL is shared: this Hermes version keys connection discovery by
name while tool registration belongs to a profile. Reusing the name causes the
second profile to lose its tools. HTTP sessions do not spawn MCP subprocesses.

`hosts/spark/services/roommate-agent.nix` configures Hermes's native
multiplexed profiles. Roomcast contains no messaging transport, identities or
chat permissions. The existing Photon connection stays on the personal profile.
Telegram routes to `roommates`, which exposes only eight Roomcast MCP tools:
search, play, status, control, seek, subtitles, sources and browse. The profile
has its own working directory, instructions and shared group conversation state. Personal
memory and plugins are disabled; Hermes supplies native shared Codex OAuth.
Its Nix-selected skills are `hermes-agent` and `roomcast`, with bundled seeding,
project discovery and skill-creation nudges disabled.

Profiles share a gateway process and Unix user. They separate context and tools,
not filesystem or process access. Guests have no terminal, personal browser,
knowledge-base, delegation or outbound messaging tool. Roomcast separately runs
as its own service user with its own browser state.

### Enrollment

The existing `@sparkotron_bot` is enrolled in Home (`-5343368090`). Nix
owns this exact group allowlist; the recovered token and owner ID remain in
`secrets/hosts/spark/hermes-telegram.env`. Roommates' Telegram DMs and other groups are
rejected; the owner's Telegram DM reaches the TV profile. Photon remains configured independently for Hari.

Ordinary group messages are TV requests; no mention or reply is required.
Nix sets `require_mention = false`. Telegram must also deliver ordinary messages:
disable privacy for `@sparkotron_bot` using BotFather's `/setprivacy`, then remove
and re-add the bot if needed for the existing group. Telegram owns that account
setting; it is not a Hermes or Nix option. Do not grant group-admin powers just
to receive ordinary messages. Use `/whoami@sparkotron_bot` for identity.

Members of the enrolled group, including later additions, can control the TV.
Guests can use `/help` and `/whoami`, but cannot change profiles or configuration.
The owner retains native admin commands. Remove the group from both allowlists
and redeploy to revoke requests; that does not stop existing playback.

Acceptance requires a group request, proof that the `roommates` profile handled
it with only Roomcast tools, and a reply delivered to the same group. Check a
real status request before asking for disruptive playback changes.

### Network policy

Spark applies an atomic nftables output policy for the Roomcast service user:
DNS through the local resolver, SSDP, Roku ECP in the configured discovery networks,
responses from the media port, and public HTTPS. Other local, tailnet and private
destinations are blocked. This table coexists with the existing NixOS firewall.

A real group request after deployment is still required to verify Photon delivery.
Native YouTube playback has been verified; direct website playback and precise
YouTube seeking retain the acceptance steps above.
