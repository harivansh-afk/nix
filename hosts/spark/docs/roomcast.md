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

## Shared chat

This service integration does not authorize roommates. Personal Hermes currently
has broad tools; do not expand its Photon allowlist for TV sharing. Group routing
must check both sender and chat IDs and use a separate runtime exposing only
Roomcast tools, with separate memory and no personal browser, shell or KB access.
That runtime and its group enrollment still need implementation and acceptance.
