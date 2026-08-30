# harivan.sh: caddy serves the live website checkout's dist/ and proxies the
# page-load counter, a small python service that lives in the website repo.
{ pkgs, username, ... }:
let
  domain = "harivan.sh";
  repoDir = "/home/${username}/Documents/Git/website";
  mountDir = "/srv/harivan.sh";
  counterPort = 8230;
in
{
  services.caddy.virtualHosts."http://${domain}" = {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      root * ${mountDir}/dist

      # HTML always revalidates; assets are content-hashed and cache forever.
      @html path / */ *.html
      header @html Cache-Control "no-cache"
      @assets path *.css *.js *.woff *.woff2 *.ttf *.otf *.png *.jpg *.jpeg *.gif *.svg *.ico *.webp
      header @assets Cache-Control "public, max-age=31536000, immutable"

      handle /counter {
        reverse_proxy 127.0.0.1:${toString counterPort}
      }
      handle /counter/hit {
        reverse_proxy 127.0.0.1:${toString counterPort}
      }
      handle /status-badge {
        rewrite * /badge
        reverse_proxy https://status.${domain} {
          header_up Host status.${domain}
        }
      }
      handle {
        file_server
      }
      handle_errors {
        header Cache-Control "no-cache"
        @notFound expression {err.status_code} == 404
        rewrite @notFound /404.html
        file_server
      }
    '';
  };

  systemd.services.caddy = {
    after = [ "website-counter.service" ];
    wants = [ "website-counter.service" ];
    serviceConfig.BindReadOnlyPaths = [ "${repoDir}:${mountDir}" ];
  };

  systemd.services.website-counter = {
    description = "harivan.sh page load counter";
    wantedBy = [ "multi-user.target" ];
    environment = {
      WEBSITE_COUNTER_DATABASE = "/var/lib/website-counter/counter.sqlite3";
      WEBSITE_COUNTER_PORT = toString counterPort;
      WEBSITE_COUNTER_SEED = "1478";
      WEBSITE_COUNTER_SEED_CUTOFF = "2026-08-02T00:01:53Z";
    };
    serviceConfig = {
      DynamicUser = true;
      StateDirectory = "website-counter";
      WorkingDirectory = "/var/lib/website-counter";
      BindReadOnlyPaths = [ "${repoDir}:${mountDir}" ];
      ExecStart = "${pkgs.python3}/bin/python3 ${mountDir}/counter/counter.py";
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
}
