{ lib, pkgs, ... }:
let
  port = 8230;
  seed = 1478;
  seedCutoff = "2026-08-02T00:01:53Z";
in
{
  services.caddy.virtualHosts."http://harivan.sh".extraConfig = lib.mkBefore ''
    handle /counter {
      reverse_proxy 127.0.0.1:${toString port}
    }
    handle /counter/hit {
      reverse_proxy 127.0.0.1:${toString port}
    }
  '';

  systemd.services.website-counter = {
    description = "harivan.sh page load counter";
    wantedBy = [ "multi-user.target" ];
    environment = {
      WEBSITE_COUNTER_DATABASE = "/var/lib/website-counter/counter.sqlite3";
      WEBSITE_COUNTER_PORT = toString port;
      WEBSITE_COUNTER_SEED = toString seed;
      WEBSITE_COUNTER_SEED_CUTOFF = seedCutoff;
    };
    serviceConfig = {
      Type = "simple";
      DynamicUser = true;
      StateDirectory = "website-counter";
      WorkingDirectory = "/var/lib/website-counter";
      ExecStart = "${pkgs.python3}/bin/python3 ${./website-counter.py}";
      Restart = "on-failure";
      RestartSec = 2;
      UMask = "0077";
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectControlGroups = true;
      ProtectHome = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectSystem = "strict";
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_UNIX"
      ];
    };
  };

  systemd.services.caddy = {
    after = [ "website-counter.service" ];
    wants = [ "website-counter.service" ];
  };
}
