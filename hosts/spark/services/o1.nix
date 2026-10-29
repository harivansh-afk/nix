{ pkgs, username, ... }:
let
  tailnet = import ../../../lib/tailnet.nix;
  repoDir = "/home/${username}/Documents/Git/o1";
  mountDir = "/srv/o1";
  port = 41873;
  tailnetPort = 41874;
in
{
  services.caddy.virtualHosts."http://127.0.0.1:${toString port}" = {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      root * ${mountDir}/app/build
      encode zstd gzip
      header Cache-Control "no-cache"
      @immutable path /_app/immutable/*
      header @immutable Cache-Control "public, max-age=31536000, immutable"
      file_server
    '';
  };

  systemd.services.caddy.serviceConfig.BindReadOnlyPaths = [ "${repoDir}:${mountDir}" ];

  systemd.services.o1-tailscale-serve = {
    description = "expose the O-1 dashboard on the tailnet";
    wantedBy = [ "multi-user.target" ];
    after = [
      "tailscaled.service"
      "caddy.service"
    ];
    wants = [ "tailscaled.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = "${pkgs.tailscale}/bin/tailscale wait --timeout=2m";
      ExecStart = "${pkgs.tailscale}/bin/tailscale serve --bg --https=${toString tailnetPort} http://127.0.0.1:${toString port}";
      ExecStop = "${pkgs.tailscale}/bin/tailscale serve --https=${toString tailnetPort} off";
    };
  };

  environment.etc."o1-dashboard-url".text =
    "https://spark.${tailnet.domain}:${toString tailnetPort}/\n";
}
