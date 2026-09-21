{
  config,
  pkgs,
  username,
  ...
}:
let
  port = 39473;
  home = config.users.users.${username}.home;
  state = "/var/lib/filebrowser-quantum";
  package = import ../../../pkgs/filebrowser-quantum { inherit pkgs; };
  source = name: path: {
    inherit name path;
    config = {
      defaultEnabled = true;
      rules = [
        { ignoreSymlinks = true; }
        { ignoreHidden = true; }
        {
          folderName = "node_modules";
          viewable = true;
        }
      ];
    };
  };
  settings = (pkgs.formats.yaml { }).generate "filebrowser.yaml" {
    server = {
      listen = "127.0.0.1";
      inherit port;
      externalUrl = "https://files.harivan.sh";
      database = "${state}/database.db";
      cacheDir = "/var/cache/filebrowser-quantum";
      disableUpdateCheck = true;
      disableWebDAV = true;
      sources = [
        (source "Documents" "${home}/Documents")
        (source "Downloads" "${home}/Downloads")
        (source "Uploads" "${state}/uploads")
      ];
      logging = [
        {
          levels = "info|warning|error";
          apiLevels = "error";
          noColors = true;
        }
      ];
    };
    auth = {
      adminUsername = username;
      methods = {
        password = {
          enabled = true;
          signup = false;
        };
        passkey.enabled = false;
      };
    };
    frontend = {
      name = "Files";
      disableDefaultLinks = true;
      styling.disableEventThemes = true;
    };
    userDefaults = {
      account = {
        lockPassword = true;
        disableUpdateNotifications = true;
      };
      listing = {
        viewMode = "list";
        showHidden = false;
        deleteAfterArchive = false;
      };
      ui.themeColor = "#5b84de";
    };
  };
in
{
  systemd.services.filebrowser-quantum = {
    description = "FileBrowser Quantum";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    script = ''
      export FILEBROWSER_ADMIN_PASSWORD="$(cat "$CREDENTIALS_DIRECTORY/password")"
      exec ${package}/bin/filebrowser-quantum -c ${settings}
    '';
    preStart = ''
      mkdir -p ${state}/uploads
    '';
    serviceConfig = {
      User = username;
      Group = "users";
      StateDirectory = "filebrowser-quantum";
      StateDirectoryMode = "0700";
      CacheDirectory = "filebrowser-quantum";
      CacheDirectoryMode = "0700";
      WorkingDirectory = state;
      LoadCredential = "password:${config.sops.secrets.filebrowser-password.path}";
      Restart = "on-failure";
      RestartSec = 5;
      UMask = "0077";
      ProtectSystem = "strict";
      ProtectHome = "tmpfs";
      BindPaths = [
        "${home}/Documents"
        "${home}/Downloads"
      ];
      ReadWritePaths = [
        "${home}/Documents"
        "${home}/Downloads"
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
      header Cache-Control "private, no-store"
      header X-Robots-Tag "noindex, nofollow"
      @legacy path /s/*
      respond @legacy "This Copyparty link has been retired. Ask the owner for a new share link." 410
      reverse_proxy 127.0.0.1:${toString port} {
        header_up X-Forwarded-Proto https
        header_up X-Forwarded-For {http.request.header.CF-Connecting-IP}
      }
    '';
  };
}
