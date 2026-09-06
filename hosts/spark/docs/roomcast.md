# Roomcast on Spark

The public Roomcast flake owns the application, package and NixOS module. This
repo pins its revision and configures Spark's LAN interface, TV serial, address
hint, discovery scope and Hermes integration. Hermes uses the module's package.

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

`hosts/spark/services/roommate-agent.nix` configures Hermes's native
multiplexed profiles. Roomcast contains no messaging transport, identities or
chat permissions. The existing Photon connection stays on the personal profile.
Telegram routes to `roommates`, which exposes only seven Roomcast MCP tools:
search, play, status, control, seek, sources and browse. The profile has its own
working directory, instructions and shared group conversation state. Personal
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
