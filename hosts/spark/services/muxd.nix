# muxd: the mux terminal-multiplexer session daemon.
#
# Panes in the Mac app can live on this box: the Mac's local muxd brokers to
# this one over QUIC, and the pty (with its scrollback) survives client
# disconnects here. The mux flake ships both the package and this service's
# option surface (services.muxd); we just enable it and point it at a listen
# address.
#
# Security boundary is the daemon's own auth, not the network: every QUIC
# request carries a bearer token (generated 0600 under the service's state
# dir on first start) and the client pins the self-signed cert
# trust-on-first-use. The box is reachable over Tailscale; binding 0.0.0.0
# keeps it simple and the token/TOFU pair is what actually gates access.
# `journalctl -u muxd` prints the cert pin to copy to the Mac.
{ inputs, ... }:
{
  imports = [ inputs.mux.nixosModules.muxd ];

  services.muxd = {
    enable = true;
    # muxd is a per-user daemon: every pane's shell runs as this user, in
    # their home, with their login shell. A system account gives every
    # pane a nologin shell that exits immediately.
    user = "rathi";
    listen = "0.0.0.0:4433";
    openFirewall = true;
  };
}
