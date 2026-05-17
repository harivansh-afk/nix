{
  config,
  lib,
  pkgs,
  username,
  ...
}:
let
  # The playbook content moved into indexable-inc/ix under playbook/ as part
  # of the standalone-repo merge (ix#2690). The standalone
  # indexable-inc/playbook repo is archived. This service builds and serves
  # the SvelteKit app from the playbook/ subdirectory of the local ix
  # checkout.
  #
  # The ix checkout is shared with symphony, which roots every dispatch
  # worktree under ${ixRepoDir}/.worktrees/. Worktrees are pinned to their
  # own branches, so the periodic `git reset --hard FETCH_HEAD` of the main
  # checkout below does not disturb any in-flight symphony run.
  ixRepoDir = "/home/${username}/Documents/Git/indexable/ix";
  playbookSubdir = "${ixRepoDir}/playbook";
  port = 4060;
  serveHost = "spark-ix.tail368802.ts.net";
  basePath = "/playbooks";

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

    cd ${ixRepoDir}
    auth_url="https://x-access-token:''${GITHUB_TOKEN}@github.com/indexable-inc/ix.git"

    runuser -u ${username} -- git fetch --prune --quiet "$auth_url" main

    local_sha=$(runuser -u ${username} -- git rev-parse HEAD)
    remote_sha=$(runuser -u ${username} -- git rev-parse FETCH_HEAD)

    if [ "$local_sha" = "$remote_sha" ]; then
      echo "ix up to date at $local_sha"
      exit 0
    fi

    echo "advancing ix: $local_sha -> $remote_sha"
    runuser -u ${username} -- git reset --hard --quiet FETCH_HEAD
    ${pkgs.systemd}/bin/systemctl restart playbook.service
  '';
in
{
  systemd.services.playbook = {
    description = "Indexable Playbook UI (SvelteKit adapter-node), served from indexable-inc/ix/playbook/";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      HOME = "/home/${username}";
      NODE_ENV = "production";
      PORT = toString port;
      HOST = "127.0.0.1";
      ORIGIN = "https://${serveHost}${basePath}";
      # BASE_PATH is read by playbook/svelte.config.js at build time so the
      # SvelteKit app serves at the /playbooks sub-path that tailscale-serve
      # forwards to. Keep this aligned with the public URL above.
      BASE_PATH = basePath;
      PROTOCOL_HEADER = "x-forwarded-proto";
      HOST_HEADER = "x-forwarded-host";
      CODEX_VIEWER_ENABLED = "1";
    };

    serviceConfig = {
      Type = "simple";
      User = username;
      Group = "users";
      WorkingDirectory = playbookSubdir;
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
    description = "Pull indexable-inc/ix main; restart playbook.service on advance";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = [ config.sops.secrets."symphony.env".path ];
      ExecStart = "${updateScript}";
    };
  };

  systemd.timers.playbook-update = {
    description = "Poll indexable-inc/ix main every 10 minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "10min";
      AccuracySec = "30s";
      Unit = "playbook-update.service";
    };
  };
}
