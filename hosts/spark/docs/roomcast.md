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

`hosts/spark/services/roommate-agent/` owns the iMessage integration. Roomcast
contains no chat routing, identities or permissions. The existing Photon sidecar
routes explicit DMs through the existing personal gateway allowlist. Group events
never enter that gateway, including groups where Hari sends a message. Unknown
chat types fail closed.

After deploying this integration:

1. Create an iMessage group with the existing Spark agent and your roommates.
2. From your own authorized iMessage identity, send `/tv enable` in that group.
3. Wait for the enrollment confirmation, then ask for TV playback normally.
4. Send `/tv disable` as the owner to revoke the group, cancel active worker work
   and discard queued requests. This does not stop video already playing.

Enrollment uses trusted Photon sender and chat IDs. Only identities in the
existing explicit `PHOTON_ALLOWED_USERS` can enroll or revoke. Every member of an
enrolled group, including members added later, can control the TV there. Roommate
DMs keep the personal gateway's existing restrictions. Do not add roommates to
`PHOTON_ALLOWED_USERS`: that is the owner list, not the TV guest list. Other slash
commands are withheld from the TV runtime. Replies use the originating SDK space;
the model receives no destination-selection or messaging tool.

The router retains enrollment, recent message IDs and twelve user/assistant
messages per group in private `roommates/groups.json` beneath Hermes's state
directory. It ignores events older than five minutes, limits the shared queue to
four requests, and serializes TV work. A restart drops pending requests; users can
retry with a new message. Attachments, reactions and voice messages are not routed
to the TV agent in this version.

Each turn starts a fresh Bubblewrap sandbox running Hermes's pinned Python agent
with exactly seven Roomcast tools. Tool discovery fails closed if that set changes.
The sandbox has no personal home, memory, browser profile, Photon credentials,
chat enrollment state or general computer tools. The trusted launcher refreshes
Codex OAuth outside the sandbox and passes one access token over stdin. No refresh
token or credentials are written into the worker filesystem or Nix store. The
worker uses the personal agent's configured model through the Codex provider.
Only bounded group text history crosses the boundary; worker state is ephemeral.

Roomcast's service runs as its own user. Spark applies an atomic nftables output
policy for that user: DNS through the local resolver, SSDP, Roku ECP in the
configured discovery networks, responses from the media port, and public HTTPS.
Other local, tailnet and private destinations are blocked. This table coexists
with the existing NixOS firewall; it does not switch firewall backends. The worker
itself shares host networking for the model API, but has no network/browser tool
outside the constrained Roomcast API. This is a capability boundary and filesystem
sandbox, not a separate machine or a defense against a kernel exploit.

Validation before deployment: router authorization/replay/revocation tests,
worker tool-set and hidden-home checks, a real Astra status request, refusal of a
personal-credential request, and confirmed native YouTube playback. The rendered
network rules load in an isolated network namespace on Spark's running kernel.
The actual Photon group enrollment/reply path still needs a real group message
after deployment; local fixtures do not prove iMessage delivery.
