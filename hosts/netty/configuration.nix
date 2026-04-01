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
  sandboxDomain = "netty.harivan.sh";
  forgejoDomain = "git.harivan.sh";
  vaultDomain = "vault.harivan.sh";
  forgejoApiUrl = "http://127.0.0.1:19300";
  sandboxAgentPackage = pkgs.callPackage ../../pkgs/sandbox-agent { };
  sandboxAgentDir = "/home/${username}/.config/sandbox-agent";
  sandboxAgentPath =
    packageSets.core
    ++ packageSets.extras
    ++ [
      pkgs.bubblewrap
      pkgs.git
      pkgs.nodejs
      pkgs.pnpm
      sandboxAgentPackage
    ];
  sandboxAgentEnvCheck = pkgs.writeShellScript "sandbox-agent-env-check" ''
    [ -f "${sandboxAgentDir}/agent.env" ] && [ -f "${sandboxAgentDir}/public.env" ]
  '';
  sandboxAgentWrapper = pkgs.writeShellScript "sandbox-agent-public" ''
    set -euo pipefail
    set -a
    . "${sandboxAgentDir}/public.env"
    . "${sandboxAgentDir}/agent.env"
    set +a
    exec sandbox-agent server \
      --host 127.0.0.1 \
      --port "''${SANDBOX_AGENT_PORT}" \
      --token "''${SANDBOX_AGENT_TOKEN}"
  '';
  sandboxCorsProxy = pkgs.writeText "sandbox-agent-cors-proxy.mjs" ''
    import http from "node:http";

    const listenHost = "127.0.0.1";
    const listenPort = 2468;
    const targetHost = "127.0.0.1";
    const targetPort = 2470;

    function setCorsHeaders(headers, req) {
      headers["access-control-allow-origin"] = "*";
      headers["access-control-allow-methods"] = "GET,POST,PUT,PATCH,DELETE,OPTIONS";
      headers["access-control-allow-headers"] =
        req.headers["access-control-request-headers"] || "authorization,content-type";
      headers["access-control-max-age"] = "86400";
      return headers;
    }

    const server = http.createServer((req, res) => {
      if (req.method === "OPTIONS") {
        res.writeHead(204, setCorsHeaders({}, req));
        res.end();
        return;
      }

      const proxyReq = http.request(
        {
          host: targetHost,
          port: targetPort,
          method: req.method,
          path: req.url,
          headers: {
            ...req.headers,
            host: `''${targetHost}:''${targetPort}`,
          },
        },
        (proxyRes) => {
          res.writeHead(
            proxyRes.statusCode || 502,
            setCorsHeaders({ ...proxyRes.headers }, req),
          );
          proxyRes.pipe(res);
        },
      );

      proxyReq.on("error", () => {
        res.writeHead(502, setCorsHeaders({ "content-type": "text/plain" }, req));
        res.end("Upstream request failed");
      });

      req.pipe(proxyReq);
    });

    server.listen(listenPort, listenHost);
  '';
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

  users.users.root = {
    hashedPassword = "$6$T3d8stz8lq3N./Q/$QFDRHskykhr.SFozDTfX0ziisfz7ofRfyV/0tfCsBAxrZteJFj4sPTohmAiN3bOZOSVNkmaOD61vTFCMyuQ.S1";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFbL9gJC0IPX6XUdJSWBovp+zmHvooMmvl91QG3lllwN rathiharivansh@gmail.com"
    ];
  };

  users.users.${username} = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "docker"
    ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFbL9gJC0IPX6XUdJSWBovp+zmHvooMmvl91QG3lllwN rathiharivansh@gmail.com"
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

  virtualisation.docker.enable = true;

  environment.systemPackages = packageSets.extras ++ [
    pkgs.bubblewrap
    pkgs.pnpm
    pkgs.nodejs
    pkgs.php
    sandboxAgentPackage
  ];

  systemd.tmpfiles.rules = [
    "L /usr/bin/bwrap - - - - ${pkgs.bubblewrap}/bin/bwrap"
    "z /var/lib/vaultwarden/vaultwarden.env 0600 vaultwarden vaultwarden -"
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

    virtualHosts.${sandboxDomain} = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:2470";
    };

    virtualHosts.${forgejoDomain} = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:19300";
    };

    virtualHosts.${vaultDomain} = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:8222";
    };
  };

  # --- Vaultwarden ---
  services.vaultwarden = {
    enable = true;
    backupDir = "/var/backup/vaultwarden";
    environmentFile = "/var/lib/vaultwarden/vaultwarden.env";
    config = {
      DOMAIN = "https://${vaultDomain}";
      SIGNUPS_ALLOWED = false;
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = 8222;
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
      repository = {
        FORCE_PRIVATE = true;
        DEFAULT_PRIVATE = "private";
        DEFAULT_PUSH_CREATE_PRIVATE = true;
      };
      server = {
        DOMAIN = forgejoDomain;
        ROOT_URL = "https://${forgejoDomain}/";
        HTTP_PORT = 19300;
        SSH_DOMAIN = forgejoDomain;
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
    path = [
      pkgs.curl
      pkgs.jq
      pkgs.coreutils
      pkgs.gnused
    ];
    script = ''
      set -euo pipefail

      api_call() {
        local response http_code body
        response=$(curl -sS -w "\n%{http_code}" "$@")
        http_code=$(printf '%s\n' "$response" | tail -n1)
        body=$(printf '%s\n' "$response" | sed '$d')
        if [ "$http_code" -ge 400 ]; then
          printf '[forgejo-mirror-sync] HTTP %s\n' "$http_code" >&2
          printf '%s\n' "$body" >&2
          return 1
        fi
        printf '%s' "$body"
      }

      gh_user=$(api_call -H "Authorization: token $GITHUB_TOKEN" \
        "https://api.github.com/user" | jq -r '.login')

      repos_file=$(mktemp)
      trap 'rm -f "$repos_file"' EXIT

      page=1
      while true; do
        batch=$(api_call -H "Authorization: token $GITHUB_TOKEN" \
          "https://api.github.com/user/repos?per_page=100&page=$page&visibility=all&affiliation=owner,organization_member")
        count=$(printf '%s' "$batch" | jq length)
        [ "$count" -eq 0 ] && break
        printf '%s' "$batch" | jq -r '.[] | [.full_name, .clone_url] | @tsv' >> "$repos_file"
        page=$((page + 1))
      done

      sort -u "$repos_file" -o "$repos_file"

      while IFS=$'\t' read -r full_name clone_url; do
        repo_owner="''${full_name%%/*}"
        repo_name="''${full_name#*/}"

        if [ "$repo_owner" = "$gh_user" ]; then
          forgejo_repo_name="$repo_name"
        else
          forgejo_repo_name="$repo_owner--$repo_name"
        fi

        status=$(curl -sS -o /dev/null -w '%{http_code}' \
          -H "Authorization: token $FORGEJO_TOKEN" \
          "${forgejoApiUrl}/api/v1/repos/$FORGEJO_OWNER/$forgejo_repo_name" || true)

        if [ "$status" = "404" ]; then
          api_call -X POST \
            -H "Authorization: token $FORGEJO_TOKEN" \
            -H "Content-Type: application/json" \
            "${forgejoApiUrl}/api/v1/repos/migrate" \
            -d "$(jq -n \
              --arg addr "$clone_url" \
              --arg name "$forgejo_repo_name" \
              --arg owner "$FORGEJO_OWNER" \
              --arg token "$GITHUB_TOKEN" \
              '{
                clone_addr: $addr,
                repo_name: $name,
                repo_owner: $owner,
                private: true,
                mirror: true,
                auth_token: $token,
                service: "github"
              }')" \
            > /dev/null
          echo "Created mirror: $full_name -> $FORGEJO_OWNER/$forgejo_repo_name"
        else
          if ! api_call -X POST \
            -H "Authorization: token $FORGEJO_TOKEN" \
            "${forgejoApiUrl}/api/v1/repos/$FORGEJO_OWNER/$forgejo_repo_name/mirror-sync" \
            > /dev/null; then
            echo "Failed mirror sync: $full_name -> $FORGEJO_OWNER/$forgejo_repo_name" >&2
            continue
          fi
          echo "Synced mirror: $full_name -> $FORGEJO_OWNER/$forgejo_repo_name"
        fi
      done < "$repos_file"
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
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    path = sandboxAgentPath;
    serviceConfig = {
      Type = "simple";
      User = username;
      Group = "users";
      WorkingDirectory = "/home/${username}";
      ExecCondition = sandboxAgentEnvCheck;
      ExecStart = sandboxAgentWrapper;
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  systemd.services.sandbox-cors-proxy = {
    description = "Sandbox CORS Proxy";
    after = [ "sandbox-agent.service" ];
    requires = [ "sandbox-agent.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      User = username;
      Group = "users";
      WorkingDirectory = "/home/${username}";
      ExecCondition = sandboxAgentEnvCheck;
      ExecStart = "${pkgs.nodejs}/bin/node ${sandboxCorsProxy}";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  system.configurationRevision = self.rev or self.dirtyRev or null;
  system.stateVersion = "24.11";
}
