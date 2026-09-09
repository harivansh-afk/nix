{ pkgs, loopbackVhost, ... }:
{
  virtualisation.oci-containers = {
    backend = "podman";
    containers = {
      excalidash-backend = {
        image = "docker.io/zimengxiong/excalidash-backend@sha256:64196bbd58f81002988aaad1a7485d822a0fafb600efda9e4ae2275b6666e91f";
        environment = {
          NODE_ENV = "production";
          PORT = "8000";
          DATABASE_PROVIDER = "sqlite";
          DATABASE_URL = "file:/app/prisma/dev.db";
          AUTH_MODE = "local";
          FRONTEND_URL = "https://draw.harivan.sh";
          TRUST_PROXY = "2";
          UPDATE_CHECK_OUTBOUND = "false";
        };
        volumes = [
          "/var/lib/excalidash/prisma:/app/prisma"
          "/var/lib/excalidash/uploads:/app/uploads"
        ];
        networks = [ "excalidash" ];
        extraOptions = [ "--init" ];
      };
      excalidash-frontend = {
        image = "docker.io/zimengxiong/excalidash-frontend@sha256:482be5d38f81db0abcbb966219e3a18b298e5be2fab3d710cb9f58f912ffd1be";
        dependsOn = [ "excalidash-backend" ];
        environment.BACKEND_URL = "excalidash-backend:8000";
        ports = [ "127.0.0.1:19462:80" ];
        networks = [ "excalidash" ];
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/excalidash 0700 root root -"
    "d /var/lib/excalidash/prisma 0700 1001 1001 -"
    "d /var/lib/excalidash/uploads 0700 1001 1001 -"
    "d /var/backup/excalidash 0700 root root -"
  ];

  systemd.services.excalidash-network = {
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.podman}/bin/podman network create --ignore excalidash";
    };
  };

  systemd.services.podman-excalidash-backend = {
    requires = [ "excalidash-network.service" ];
    after = [
      "excalidash-network.service"
      "systemd-tmpfiles-setup.service"
    ];
  };

  systemd.services.podman-excalidash-frontend = {
    partOf = [ "podman-excalidash-backend.service" ];
  };

  systemd.services.excalidash-backup = {
    description = "Back up the ExcaliDash SQLite database";
    serviceConfig = {
      Type = "oneshot";
      UMask = "0077";
    };
    path = [
      pkgs.sqlite
      pkgs.coreutils
      pkgs.findutils
    ];
    script = ''
      test -f /var/lib/excalidash/prisma/dev.db
      backup="/var/backup/excalidash/$(date -u +%Y-%m-%dT%H-%M-%SZ).sqlite"
      sqlite3 /var/lib/excalidash/prisma/dev.db ".backup '$backup'"
      test "$(sqlite3 "$backup" 'PRAGMA quick_check;')" = ok
      find /var/backup/excalidash -maxdepth 1 -type f -name '*.sqlite' -mtime +14 -delete
    '';
  };

  systemd.timers.excalidash-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 04:00:00 UTC";
      Persistent = true;
    };
  };

  services.caddy.virtualHosts."http://draw.harivan.sh" = (loopbackVhost 19462) // {
    extraConfig = ''
      @insecure header X-Forwarded-Proto http
      redir @insecure https://draw.harivan.sh{uri} 308
      header Strict-Transport-Security "max-age=31536000"
      encode zstd gzip
      reverse_proxy 127.0.0.1:19462 {
        header_up X-Forwarded-Proto https
        header_up X-Forwarded-For {http.request.header.CF-Connecting-IP}
      }
    '';
  };
}
