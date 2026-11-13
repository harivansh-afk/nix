# omnipresent (git.harivan.sh/harivansh-afk/omnipresent) runs from its checkout under process-compose while it is
# being built; this only makes it reachable from the phone over the tailnet:
#   https://spark.<tailnet>:8780 -> 127.0.0.1:8780  the conductor's token endpoint
#   https://spark.<tailnet>:7443 -> 127.0.0.1:7880  LiveKit signalling (wss)
#   UDP 7882 on tailscale0                           LiveKit media
{ config, lib, ... }:
let
  tailscale = config.services.tailscale.package;

  serve = name: port: target: {
    "omnipresent-serve-${name}" = {
      description = "Tailscale Serve for omnipresent ${name}";
      after = [ "tailscaled.service" ];
      requires = [ "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStartPre = "${tailscale}/bin/tailscale wait";
        ExecStart = "${tailscale}/bin/tailscale serve --bg --https=${toString port} ${target}";
        ExecStop = "${tailscale}/bin/tailscale serve --https=${toString port} off";
      };
    };
  };
in
{
  networking.firewall.interfaces.tailscale0.allowedUDPPorts = [ 7882 ];

  systemd.services = lib.mkMerge [
    (serve "tokens" 8780 "http://127.0.0.1:8780")
    (serve "livekit" 7443 "http://127.0.0.1:7880")
  ];
}
