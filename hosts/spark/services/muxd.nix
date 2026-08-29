# muxd for panes that live on this box; the Mac's muxd brokers to it over
# QUIC. Access is gated by the daemon's bearer token + TOFU cert pin, not
# the firewall (`journalctl -u muxd` prints the pin).
{ inputs, ... }:
{
  imports = [ inputs.mux.nixosModules.muxd ];

  services.muxd = {
    enable = true;
    # Every pane's shell runs as this user; a system account would get nologin.
    user = "rathi";
    listen = "0.0.0.0:4433";
    openFirewall = true;
  };
}
