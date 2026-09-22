{
  config,
  inputs,
  pkgs,
  username,
  ...
}:
let
  package = inputs.sharefs.packages.${pkgs.stdenv.hostPlatform.system}.default;
  port = 39473;
  home = config.users.users.${username}.home;
  root = "/run/sharefs/files";
  settings = (pkgs.formats.yaml { }).generate "sharefs.yaml" {
    serve-path = root;
    bind = "127.0.0.1";
    inherit port;
    share-db = "/var/lib/sharefs/shares.db";
    allow-upload = true;
    allow-delete = true;
    hidden = [ ".*" ];
  };
in
{
  systemd.services.sharefs = {
    description = "sharefs";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network.target"
      "filebrowser-quantum.service"
    ];
    script = ''
      password="$(cat "$CREDENTIALS_DIRECTORY/password")"
      if [[ -z "$password" || "$password" == *'|'* || "$password" == *'@'* || "$password" == *$'\n'* || "$password" == *$'\r'* ]]; then
        echo "sharefs: invalid account credential" >&2
        exit 1
      fi
      export SHAREFS_AUTH="${username}:$password@/:rw"
      exec ${package}/bin/sharefs --config ${settings}
    '';
    serviceConfig = {
      User = username;
      Group = "users";
      RuntimeDirectory = "sharefs";
      RuntimeDirectoryMode = "0700";
      StateDirectory = "sharefs";
      StateDirectoryMode = "0700";
      WorkingDirectory = "/var/lib/sharefs";
      LoadCredential = "password:${config.sops.secrets.filebrowser-password.path}";
      Restart = "on-failure";
      RestartSec = 5;
      UMask = "0077";
      ProtectSystem = "strict";
      ProtectHome = true;
      BindPaths = [
        "${home}/Documents:${root}/Documents"
        "${home}/Downloads:${root}/Downloads"
        "/var/lib/filebrowser-quantum/uploads:${root}/Uploads"
      ];
      PrivateTmp = true;
      PrivateDevices = true;
      NoNewPrivileges = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
      CapabilityBoundingSet = "";
      RestrictAddressFamilies = [
        "AF_UNIX"
        "AF_INET"
        "AF_INET6"
      ];
    };
  };

  services.caddy.virtualHosts."http://files.harivan.sh" = {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      header X-Robots-Tag "noindex, nofollow"
      header Referrer-Policy "no-referrer"
      @copyparty path /s/*
      respond @copyparty "This Copyparty link has been retired. Ask the owner for a new share link." 410
      @quantum path /api/* /public/* /login /settings/* /files/*
      @quantumPrivate not path /public/static/*
      @sharefsPrivate not path /__sharefs_v*__/*
      handle @quantum {
        header @quantumPrivate >Cache-Control "private, no-store"
        reverse_proxy 127.0.0.1:39476 {
          header_up X-Forwarded-Proto https
          header_up X-Forwarded-For {http.request.header.CF-Connecting-IP}
        }
      }
      handle {
        header @sharefsPrivate >Cache-Control "private, no-store"
        header Content-Security-Policy "script-src https://files.harivan.sh/__sharefs_v${package.version}__/; base-uri 'none'"
        reverse_proxy 127.0.0.1:${toString port} {
          header_up X-Forwarded-Proto https
          header_up X-Forwarded-For {http.request.header.CF-Connecting-IP}
        }
      }
    '';
  };
}
