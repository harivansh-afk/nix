# AirPlay discovery on Spark

The `airplay-at-the-crib` flake input owns the compiled Bluetooth discovery
daemon, package, tests and NixOS module. Spark enables it in
`hosts/spark/services/airplay-beacon.nix`, using the same Roku identity and
bounded LAN discovery ranges as Roomcast. The beacon does not depend on the
Roomcast process and does not control or relay playback.

Nearby Apple devices with Bluetooth enabled can discover the Roku, then send
media directly to it over the apartment network. Users open Control Center →
Screen Mirroring and choose the Roku. They still need direct network access to
the TV. Spark must stay on for reliable new discovery. Established media does
not pass through Spark. Keep the TV on for initial testing; Fast TV Start can
keep its network service available in standby, with additional standby power.

This is part of the normal persistent Spark configuration. A test-only
activation was repeatedly removed by subsequent normal deployments; do not
maintain the production service that way.

## Operation

```sh
systemctl status airplay-beacon bluetooth
journalctl -u airplay-beacon -n 30 --no-pager
busctl get-property org.bluez /org/bluez/hci0 org.bluez.LEAdvertisingManager1 ActiveInstances
systemctl show airplay-beacon -p MemoryCurrent -p MemoryPeak -p CPUUsageNSec -p NRestarts
```

Healthy checks run once per minute. Unavailable receivers are withdrawn, then
known addresses are retried every 15 seconds. DHCP recovery uses the last
verified address in `/var/lib/airplay-beacon/address.json`, matching ARP neighbors,
then the configured fallback ranges at most once per five minutes. Every
address is checked against the original Roku serial before being advertised.

The unit starts at boot and follows Bluetooth daemon restarts. It runs as an
unprivileged dynamic user with a private state directory, no listening network
ports, a 64 MiB hard memory limit, a 32 MiB pressure threshold, and a CPU quota
of 5% of one core. These are ceilings, not expected usage.

## Acceptance

Hari confirmed Mac-to-Roku mirroring through the prototype on September 25,
2026. The packaged daemon preserves that Bluetooth payload. Its checks include
an isolated D-Bus lifecycle test and bounded recovery tests. After deployment,
verify the exact package path, active advertisement, and resource use separately.
Phone compatibility, apartment-wide Bluetooth coverage, and TV standby behavior
require their own device tests; registration alone is not playback evidence.

The original Python prototype used 3.672 CPU seconds over 17 minutes 19 seconds,
with about 64 MiB peak service memory. Record compiled-service measurements with
their observation window, rather than treating resource limits as measurements.
