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
  # The deployed branch is `dev`: ix's release flow lands work on `dev`
  # first and only fast-forwards `main` on cut, so tracking `dev` keeps
  # the spark playbook UI on the latest in-progress build.
  #
  # The ix checkout is shared with symphony, which roots every dispatch
  # worktree under ${ixRepoDir}/.worktrees/. Worktrees are pinned to their
  # own branches, so the periodic `git reset --hard FETCH_HEAD` of the
  # top-level checkout below does not disturb any in-flight symphony run.
  ixRepoDir = "/home/${username}/Documents/Git/indexable/ix";
  playbookSubdir = "${ixRepoDir}/playbook";
  port = 4060;
  serveHost = "spark-ix.tail368802.ts.net";
  trackedBranch = "dev";

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

    runuser -u ${username} -- git fetch --prune --quiet "$auth_url" ${trackedBranch}

    local_sha=$(runuser -u ${username} -- git rev-parse HEAD)
    remote_sha=$(runuser -u ${username} -- git rev-parse FETCH_HEAD)

    if [ "$local_sha" = "$remote_sha" ]; then
      echo "ix up to date at $local_sha (tracking ${trackedBranch})"
      exit 0
    fi

    echo "advancing ix (${trackedBranch}): $local_sha -> $remote_sha"
    runuser -u ${username} -- git reset --hard --quiet FETCH_HEAD
    # Clear any prior rate-limit state from StartLimitBurst so a new
    # commit always gets a fresh start attempt, even if the previous
    # build was failing in a tight loop.
    ${pkgs.systemd}/bin/systemctl reset-failed playbook.service
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
      # Playbook serves at the deploy host's root so the public URL
      # matches what `vite dev` produces locally. No BASE_PATH; the
      # SvelteKit config falls through to `paths.base = ''` and the
      # tailscale-serve mount for port 8443 forwards `/` directly to
      # this app.
      ORIGIN = "https://${serveHost}";
      PROTOCOL_HEADER = "x-forwarded-proto";
      HOST_HEADER = "x-forwarded-host";
      CODEX_VIEWER_ENABLED = "1";
    };

    # Cap the restart loop at 5 attempts per ix SHA. A failing
    # `bun run build` (e.g. a SvelteKit prerender throwing on a stale
    # embed) was previously free to retry every ~28s indefinitely, each
    # attempt allocating ~1.4 GiB while holding the build CPU hot.
    #
    # StartLimitIntervalSec = infinity makes the burst counter never
    # decay on its own. After 5 failed starts the unit stays in failed
    # state until something explicitly calls `systemctl reset-failed`;
    # the playbook-update script does exactly that when (and only when)
    # the tracked ix branch advances. Net effect: a broken commit on
    # `dev` burns 5 attempts and then stops, and the next good commit
    # gets a fresh 5 attempts.
    unitConfig = {
      StartLimitBurst = 5;
      StartLimitIntervalSec = "infinity";
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
    description = "Pull indexable-inc/ix ${trackedBranch}; restart playbook.service on advance";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = [ config.sops.secrets."symphony.env".path ];
      ExecStart = "${updateScript}";
    };
  };

  systemd.timers.playbook-update = {
    description = "Poll indexable-inc/ix ${trackedBranch} every 10 minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "10min";
      AccuracySec = "30s";
      Unit = "playbook-update.service";
    };
  };
}
