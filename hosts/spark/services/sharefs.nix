{
  config,
  inputs,
  lib,
  pkgs,
  username,
  ...
}:
let
  package = inputs.sharefs.packages.${pkgs.stdenv.hostPlatform.system}.default;
  port = 39473;
  home = config.users.users.${username}.home;
  root = "/run/sharefs/files";
  sources = {
    Documents = "${home}/Documents";
    Downloads = "${home}/Downloads";
    Uploads = "${home}/Uploads";
  };
  settings = (pkgs.formats.yaml { }).generate "sharefs.yaml" {
    serve-path = root;
    bind = "127.0.0.1";
    inherit port;
    public-url = "https://files.harivan.sh";
    share-key-file = config.sops.secrets.sharefs-signing-key.path;
    control-socket = "/run/sharefs/control.sock";
    share-roots = sources;
    allow-upload = true;
    allow-edit = true;
    allow-rename = true;
    hidden = [ ".*" ];
  };
in
{
  environment.systemPackages = [ package ];

  system.activationScripts.sharefs-uploads = {
    deps = [ "users" ];
    text = ''
      ${pkgs.util-linux}/bin/runuser -u ${username} -- ${pkgs.bash}/bin/bash <<'SHAREFS_UPLOADS'
      set -eu
      if [ -L /var/lib/sharefs/uploads ] || [ -L "${home}/Uploads" ]; then
        echo "sharefs: upload directories must not be symlinks" >&2
        exit 1
      fi
      if [ -d /var/lib/sharefs/uploads ]; then
        if [ -e "${home}/Uploads" ]; then
          echo "sharefs: both upload directories exist; refusing to overwrite files" >&2
          exit 1
        fi
        ${pkgs.coreutils}/bin/mv -T --update=none-fail -- /var/lib/sharefs/uploads "${home}/Uploads"
      fi
      ${pkgs.coreutils}/bin/install -d -m 0700 "${home}/Uploads"
      SHAREFS_UPLOADS
    '';
  };

  systemd.services.sharefs = {
    description = "sharefs";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
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
      LoadCredential = "password:${config.sops.secrets.sharefs-password.path}";
      Restart = "on-failure";
      RestartSec = 5;
      UMask = "0077";
      ProtectSystem = "strict";
      ProtectHome = true;
      BindPaths = lib.mapAttrsToList (name: path: "${path}:${root}/${name}") sources;
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
    logFormat = ''
      output file /var/log/caddy/access-http:__files.harivan.sh.log
      format filter {
        wrap json
        fields {
          request>uri query {
            replace token REDACTED
          }
        }
      }
    '';
    extraConfig = ''
      header X-Robots-Tag "noindex, nofollow"
      header Referrer-Policy "no-referrer"
      @private not path /__sharefs_v*__/*
      header @private >Cache-Control "private, no-store"
      header Content-Security-Policy "script-src https://files.harivan.sh/__sharefs_v${package.version}__/; base-uri 'none'"
      reverse_proxy 127.0.0.1:${toString port} {
        header_up X-Forwarded-Proto https
        header_up X-Forwarded-For {http.request.header.CF-Connecting-IP}
      }
    '';
  };
}
