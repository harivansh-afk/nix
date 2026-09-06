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
chat permissions. Photon uses the unmodified upstream sidecar.

The existing owner's DM routes to the default personal profile. Every other
Photon chat routes to `roommates`, which exposes only seven Roomcast MCP tools:
search, play, status, control, seek, sources and browse. The profile has its own
working directory, instructions and conversation state; personal memory and
plugins are disabled. Hermes supplies its native shared Codex OAuth fallback.
There is one Photon connection, and Hermes replies to the originating chat.
Members of a group share its conversation session through Hermes's native setting.
Its Nix-selected skills are only `hermes-agent` and `roomcast`; bundled seeding,
project skill discovery and skill-creation nudges are disabled for this profile.

Profiles share a gateway process and Unix user. They separate agent context and
tool availability; they are not a filesystem or process sandbox. Guests have no
terminal, personal browser, knowledge-base, delegation or outbound messaging tool.
Roomcast's service separately runs as its own user with its own browser state.

### Enrollment

After merging and deploying:

1. Create the iMessage group with the existing Spark agent and your roommates.
2. Send `/whoami` yourself in that group and record its chat ID.
3. Add `ROOMMATE_CHAT_IDS=<chat ID>` to the existing encrypted
   `secrets/hosts/spark/hermes-photon.env`, then deploy that configuration change.
   Multiple chat IDs are comma-separated. Never use `*`.
4. Have a roommate ask for playback and confirm the reply arrives in that group.

Every member of an allowed group, including members added later, can control the
TV there. Their DMs and other groups remain unauthorized. Keep
`PHOTON_ALLOWED_USERS` restricted to the owner; do not add roommates. Native slash
permissions allow guests only `/help` and `/whoami`; the owner retains admin
commands. Remove a chat ID and redeploy to revoke future requests. Revocation does
not cancel a request already running or stop playback.

The owner DM route uses the existing `PHOTON_HOME_CHANNEL` phone number with
Photon's `any;-;` chat-ID prefix, verified against this account's session metadata.
If Photon changes that identifier, update the route; unmatched owner chats get
the TV profile. The managed configuration expands identifiers from the service's
private environment, so no phone numbers or group IDs enter the Nix store.
An unset `ROOMMATE_CHAT_IDS` grants no guest access.

### Network policy

Spark applies an atomic nftables output policy for the Roomcast service user:
DNS through the local resolver, SSDP, Roku ECP in the configured discovery networks,
responses from the media port, and public HTTPS. Other local, tailnet and private
destinations are blocked. This table coexists with the existing NixOS firewall.

A real group request after deployment is still required to verify Photon delivery.
Native YouTube playback has been verified; direct website playback and precise
YouTube seeking retain the acceptance steps above.
