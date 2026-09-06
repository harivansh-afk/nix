# Roomcast on Spark

The public [Roomcast flake](https://git.harivan.sh/harivansh-afk/roomcast) owns the
application, package and NixOS module. This repo pins its revision and supplies
Spark's TV identity, network settings and Hermes integration in
`hosts/spark/services/roomcast.nix`. Hermes uses the module's selected package,
including any `services.roomcast.package` override. Upstream changes deploy only
after updating the flake lock and switching Spark.

## Network prerequisite

The configured Spark and Roku addresses are observed DHCP leases, not verified
reservations. Reserve both with the network operator before relying on unattended
operation. A changed Spark address breaks the advertised media URL; a changed Roku
address breaks control and its firewall rule. These are deployment settings, never
model tool arguments. The serial check prevents accidentally targeting another TV;
it is not cryptographic authentication against a malicious LAN peer.

Required paths are Spark -> Roku TCP 8060 and Roku -> Spark TCP 18795 (the module's
`port` option). The media backend remains loopback-only (`backendPort`, default
18796); control uses `/run/roomcast/control.sock`, accessible to the roomcast group.
The LAN listener exposes only token-scoped media, never control endpoints.

Spark currently uses a /16 mask; different third octets do not prove separate
subnets. Client isolation may still apply. An SSDP probe received no responses;
automatic address discovery is neither implemented nor proven on this network.
If reservations are unavailable, dynamic discovery and listener/firewall updates
need implementation and testing. Do not assign arbitrary static addresses on a
managed network.

Live playback was verified through a temporary Mac TCP forward. After deployment,
verify fresh playback and advancing Roku position directly through Spark without
that forward. That direct return path has not yet been verified.

## Roommate access

This integration adds tools to Hari's personal Hermes agent. It does not provision
a shared-chat security boundary. Photon currently uses the personal toolset;
adding roommates to `PHOTON_ALLOWED_USERS` would grant platform-wide access.

Before onboarding roommates, implement the separate runtime and authenticated
sender-plus-chat routing described in Roomcast's README. The personal agent must
not process group messages, including Hari's messages in a group. Register the
actual group and permitted sender IDs privately, then test playback and rejection
of unauthorized senders/chats. A wake phrase or prompt is not authorization.
