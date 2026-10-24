# Roomcast on Spark

The public Roomcast flake owns the application, package and NixOS module. This
repo pins its revision and configures Spark's LAN interface, TV serial, address
hint and discovery scope.

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

## MCP endpoint

`roomcast-mcp.service` serves the Roomcast MCP application through the SDK's
Streamable HTTP transport at `http://127.0.0.1:18796/mcp`. It forwards requests
to the single playback service over `/run/roomcast/control.sock`. The endpoint
accepts local connections from root and the repo owner's UID only and has no
public route. The MCP service runs as a dynamic user with the Roomcast socket
group and has no home-directory access.

## Network policy

Spark applies an atomic nftables output policy for the Roomcast service user:
DNS through the local resolver, SSDP, Roku ECP in the configured discovery networks,
responses from the media port, and public HTTPS. Other local, tailnet and private
destinations are blocked. This table coexists with the existing NixOS firewall.
