{
  config,
  lib,
  pkgs,
  username,
  ...
}:
let
  repoDir = "/home/${username}/Documents/Git/indexable/playbook";
  port = 4060;
  serveHost = "playbook.tail368802.ts.net";

  path = lib.makeBinPath [
    pkgs.bash
    pkgs.bun
    pkgs.coreutils
    pkgs.git
    pkgs.nodejs_24
    pkgs.util-linux
  ];

  updateScript = pkgs.writeShellScript "playbook-update" ''
    set -euo pipefail
    : "''${GITHUB_TOKEN:?missing GITHUB_TOKEN in EnvironmentFile (symphony.env)}"
    export PATH=${path}

    cd ${repoDir}
    auth_url="https://x-access-token:''${GITHUB_TOKEN}@github.com/indexable-inc/playbook.git"

    runuser -u ${username} -- git fetch --prune --quiet "$auth_url" main

    local_sha=$(runuser -u ${username} -- git rev-parse HEAD)
    remote_sha=$(runuser -u ${username} -- git rev-parse FETCH_HEAD)

    if [ "$local_sha" = "$remote_sha" ]; then
      echo "playbook up to date at $local_sha"
      exit 0
    fi

    echo "advancing playbook: $local_sha -> $remote_sha"
    runuser -u ${username} -- git reset --hard --quiet FETCH_HEAD
    systemctl restart playbook.service
  '';
in
{
  services.tailscale.serve = {
    enable = true;
    services.playbook.endpoints."tcp:443" = "http://127.0.0.1:${toString port}";
  };

  systemd.services.playbook = {
    description = "Indexable Playbook UI (SvelteKit adapter-node)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      HOME = "/home/${username}";
      NODE_ENV = "production";
      PORT = toString port;
      HOST = "127.0.0.1";
      ORIGIN = "https://${serveHost}";
      PROTOCOL_HEADER = "x-forwarded-proto";
      HOST_HEADER = "x-forwarded-host";
    };

    serviceConfig = {
      Type = "simple";
      User = username;
      Group = "users";
      WorkingDirectory = repoDir;
      Environment = "PATH=${path}";
      ExecStartPre = [
        "${pkgs.bun}/bin/bun install --frozen-lockfile"
        "${pkgs.bun}/bin/bun run build"
      ];
      ExecStart = "${pkgs.nodejs_24}/bin/node build/index.js";
      Restart = "on-failure";
      RestartSec = 10;
    };
  };

  systemd.services.playbook-update = {
    description = "Pull indexable-inc/playbook main; restart playbook.service on advance";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = [ config.sops.secrets."symphony.env".path ];
      ExecStart = "${updateScript}";
    };
  };

  systemd.timers.playbook-update = {
    description = "Poll indexable-inc/playbook main every 10 minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "10min";
      AccuracySec = "30s";
      Unit = "playbook-update.service";
    };
  };
}
