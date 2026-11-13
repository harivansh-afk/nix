# omnipresent (git.harivan.sh/harivansh-afk/omnipresent) runs from its checkout under process-compose while it is
# being built; this only makes it reachable from the phone over the tailnet:
#   https://spark.<tailnet>:8780 -> 127.0.0.1:8780  the conductor's token endpoint
#   https://spark.<tailnet>:7443 -> 127.0.0.1:7880  LiveKit signalling (wss)
#   UDP 7882 on tailscale0                           LiveKit media
{ config, ... }:
let
  tailscale = "${config.services.tailscale.package}/bin/tailscale";
  # One unit, applied in order: concurrent `tailscale serve` calls fail on the config's etag.
  routes = [
    {
      port = 8780;
      target = "http://127.0.0.1:8780";
    }
    {
      port = 7443;
      target = "http://127.0.0.1:7880";
    }
  ];
in
{
  networking.firewall.interfaces.tailscale0.allowedUDPPorts = [ 7882 ];

  systemd.services.omnipresent-tailscale-serve = {
    description = "Tailscale Serve for omnipresent";
    after = [ "tailscaled.service" ];
    requires = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = "${tailscale} wait";
      ExecStart = map (r: "${tailscale} serve --bg --https=${toString r.port} ${r.target}") routes;
      ExecStop = map (r: "${tailscale} serve --https=${toString r.port} off") routes;
    };
  };
}
