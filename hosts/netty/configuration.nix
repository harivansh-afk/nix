{
  inputs,
  lib,
  modulesPath,
  pkgs,
  username,
  self,
  ...
}:
let
  packageSets = import ../../lib/package-sets.nix { inherit inputs lib pkgs; };
in
{
  imports = [
    ./hardware-configuration.nix
    ./disk-config.nix
    ../../modules/base.nix
    (modulesPath + "/profiles/minimal.nix")
    (modulesPath + "/profiles/headless.nix")
  ];

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    device = "nodev";
    configurationLimit = 3;
  };

  documentation.enable = false;
  fonts.fontconfig.enable = false;

  networking = {
    hostName = "netty";
    useDHCP = false;
    interfaces.ens3 = {
      ipv4.addresses = [
        {
          address = "152.53.195.59";
          prefixLength = 22;
        }
      ];
    };
    defaultGateway = {
      address = "152.53.192.1";
      interface = "ens3";
    };
    nameservers = [
      "1.1.1.1"
      "8.8.8.8"
    ];
    firewall.allowedTCPPorts = [
      22
      80
      443
    ];
  };

  services.qemuGuest.enable = true;

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  # Emergency console access - generate hashed password and save to Bitwarden later
  users.users.root = {
    initialPassword = "temppass123";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM6tzq33IQcurWoQ7vhXOTLjv8YkdTGb7NoNsul3Sbfu rathi@mac"
    ];
  };

  users.users.${username} = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM6tzq33IQcurWoQ7vhXOTLjv8YkdTGb7NoNsul3Sbfu rathi@mac"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  nix.settings.trusted-users = lib.mkForce [
    "root"
    username
  ];

  nix.gc.options = lib.mkForce "--delete-older-than 3d";

  nix.extraOptions = ''
    min-free = ${toString (100 * 1024 * 1024)}
    max-free = ${toString (1024 * 1024 * 1024)}
  '';

  services.journald.extraConfig = "MaxRetainedFileSec=1week";

  environment.systemPackages = packageSets.extras ++ [
    pkgs.bubblewrap
    pkgs.pnpm
    pkgs.nodejs
  ];

  systemd.tmpfiles.rules = [
    "L /usr/bin/bwrap - - - - ${pkgs.bubblewrap}/bin/bwrap"
  ];

  # --- ACME / Let's Encrypt ---
  security.acme = {
    acceptTerms = true;
    defaults.email = "rathiharivansh@gmail.com";
  };

  # --- Nginx reverse proxy ---
  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    clientMaxBodySize = "512m";

    virtualHosts."sandbox.example.dev" = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:2470";
    };

    virtualHosts."git.example.dev" = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:3000";
    };
  };

  # --- Forgejo ---
  users.users.git = {
    isSystemUser = true;
    home = "/var/lib/forgejo";
    group = "git";
    shell = "${pkgs.bash}/bin/bash";
  };
  users.groups.git = { };

  services.forgejo = {
    enable = true;
    user = "git";
    group = "git";
    settings = {
      server = {
        DOMAIN = "git.example.dev";
        ROOT_URL = "https://git.example.dev/";
        HTTP_PORT = 3000;
        SSH_DOMAIN = "git.example.dev";
      };
      service.DISABLE_REGISTRATION = true;
      session.COOKIE_SECURE = true;
      mirror = {
        DEFAULT_INTERVAL = "1h";
        MIN_INTERVAL = "10m";
      };
    };
  };

  # --- Forgejo mirror sync (hourly) ---
  systemd.services.forgejo-mirror-sync = {
    description = "Sync GitHub mirrors to Forgejo";
    after = [ "forgejo.service" ];
    requires = [ "forgejo.service" ];
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = "/etc/forgejo-mirror.env";
    };
    path = [ pkgs.curl pkgs.jq pkgs.coreutils ];
    script = ''
      set -euo pipefail

      # Fetch all GitHub repos
      page=1
      repos=""
      while true; do
        batch=$(curl -sf -H "Authorization: token $GITHUB_TOKEN" \
          "https://api.github.com/user/repos?per_page=100&page=$page&affiliation=owner")
        count=$(echo "$batch" | jq length)
        [ "$count" -eq 0 ] && break
        repos="$repos$batch"
        page=$((page + 1))
      done

      echo "$repos" | jq -r '.[].clone_url' | while read -r clone_url; do
        repo_name=$(basename "$clone_url" .git)

        # Check if mirror already exists in Forgejo
        status=$(curl -sf -o /dev/null -w '%{http_code}' \
          -H "Authorization: token $FORGEJO_TOKEN" \
          "$FORGEJO_URL/api/v1/repos/$FORGEJO_OWNER/$repo_name")

        if [ "$status" = "404" ]; then
          # Create mirror
          curl -sf -X POST \
            -H "Authorization: token $FORGEJO_TOKEN" \
            -H "Content-Type: application/json" \
            "$FORGEJO_URL/api/v1/repos/migrate" \
            -d "{
              \"clone_addr\": \"$clone_url\",
              \"auth_token\": \"$GITHUB_TOKEN\",
              \"uid\": $(curl -sf -H "Authorization: token $FORGEJO_TOKEN" "$FORGEJO_URL/api/v1/user" | jq .id),
              \"repo_name\": \"$repo_name\",
              \"mirror\": true,
              \"service\": \"github\"
            }"
          echo "Created mirror: $repo_name"
        else
          # Trigger sync on existing mirror
          curl -sf -X POST \
            -H "Authorization: token $FORGEJO_TOKEN" \
            "$FORGEJO_URL/api/v1/repos/$FORGEJO_OWNER/$repo_name/mirror-sync" || true
          echo "Synced mirror: $repo_name"
        fi
      done
    '';
  };

  systemd.timers.forgejo-mirror-sync = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
      RandomizedDelaySec = "5m";
    };
  };

  # --- Sandbox Agent (declarative systemd services) ---
  systemd.services.sandbox-agent = {
    description = "Sandbox Agent";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      User = username;
      Group = "users";
      EnvironmentFile = "/home/${username}/.config/sandbox-agent/agent.env";
      ExecStart = "/home/${username}/.local/bin/sandbox-agent";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  systemd.services.sandbox-cors-proxy = {
    description = "Sandbox CORS Proxy";
    after = [ "sandbox-agent.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      User = username;
      Group = "users";
      ExecStart = "${pkgs.nodejs}/bin/node /home/${username}/.config/sandbox-agent/cors-proxy.js";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  system.configurationRevision = self.rev or self.dirtyRev or null;
  system.stateVersion = "24.11";
}
