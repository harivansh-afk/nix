{
  config,
  lib,
  pkgs,
  username,
  ...
}:
let
  stateDir = "/var/lib/indexable-symphony";
  repoDir = "/home/${username}/Documents/Git/indexable/symphony";
  ixRepoDir = "/home/${username}/Documents/Git/indexable/ix";
  port = 4040;
  pinnedBuck2 = pkgs.callPackage ../../system/buck2.nix { };
  homeBin = pkgs.runCommand "symphony-home-bin" { } ''
    mkdir -p $out/bin
    ln -s /home/${username}/.local/share/npm/bin/codex $out/bin/codex
  '';
  forgejoSshKey = config.sops.secrets."symphony-forgejo-ssh-key".path;

  # Auto-deploy: poll indexable-inc/symphony main every 10 minutes and
  # advance the local checkout if origin/main moves. Mirrors the
  # playbook-update pattern. Refuses to advance if the local checkout
  # has uncommitted changes or has diverged from origin/main, so live
  # dev on this host (the same path symphony.service reads from) is
  # never silently clobbered. When an advance lands, restart
  # symphony.service so it rebuilds its runtime copy from the new source.
  updateScript = pkgs.writeShellScript "symphony-update" ''
    set -euo pipefail
    : "''${GITHUB_TOKEN:?missing GITHUB_TOKEN in EnvironmentFile (symphony.env)}"
    export PATH=${path}

    cd ${repoDir}

    auth_url="https://x-access-token:''${GITHUB_TOKEN}@github.com/indexable-inc/symphony.git"
    runuser -u ${username} -- git fetch --prune --quiet "$auth_url" main

    local_sha=$(runuser -u ${username} -- git rev-parse HEAD)
    remote_sha=$(runuser -u ${username} -- git rev-parse FETCH_HEAD)

    if [ "$local_sha" = "$remote_sha" ]; then
      echo "symphony up to date at $local_sha"
      exit 0
    fi

    # Refuse to clobber local work: any staged change, any unstaged
    # tracked change, or any untracked-and-not-ignored file aborts the
    # advance. Hari develops symphony in this same checkout; auto-deploy
    # must not eat a WIP.
    if ! runuser -u ${username} -- git diff --quiet \
         || ! runuser -u ${username} -- git diff --cached --quiet \
         || [ -n "$(runuser -u ${username} -- git ls-files --others --exclude-standard)" ]; then
      echo "symphony local checkout has uncommitted changes; skipping auto-deploy"
      exit 0
    fi

    # Refuse to advance if local has commits not on origin/main (a true
    # divergence, not a fast-forward). The operator should resolve by
    # hand.
    if ! runuser -u ${username} -- git merge-base --is-ancestor "$local_sha" "$remote_sha"; then
      echo "symphony local checkout has diverged from origin/main; skipping auto-deploy"
      exit 0
    fi

    echo "advancing symphony: $local_sha -> $remote_sha"
    runuser -u ${username} -- git reset --hard --quiet FETCH_HEAD
    ${pkgs.systemd}/bin/systemctl restart symphony.service
  '';
  path = lib.makeBinPath [
    pkgs.bash
    pkgs.coreutils
    pkgs.curl
    pkgs.direnv
    pkgs.fd
    pkgs.elixir_1_19
    pkgs.erlang_28
    pkgs.gh
    pkgs.git
    pkgs.jq
    pkgs.nix
    pkgs.nodejs_24
    pkgs.openssh
    pkgs.python3
    pkgs.ripgrep
    pkgs.tea
    pkgs.util-linux
    pkgs.zsh
    pkgs.mgrep
    pinnedBuck2
    homeBin
  ];
in
{
  systemd.tmpfiles.rules = [
    "d ${stateDir} 0750 ${username} users -"
    "d ${stateDir}/log 0750 ${username} users -"
    "d ${stateDir}/runtime 0750 ${username} users -"
    "d ${ixRepoDir}/.worktrees 0750 ${username} users -"
  ];

  systemd.services.symphony = {
    description = "Indexable Symphony worker";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      HOME = "/home/${username}";
      SYMPHONY_STATE_DIR = stateDir;
      SYMPHONY_RUNTIME_DIR = "${stateDir}/runtime";
      SYMPHONY_WORKSPACE_ROOT = "${ixRepoDir}/.worktrees";
      SYMPHONY_LOGS_ROOT = "${stateDir}/log";
      SYMPHONY_IX_REPO = ixRepoDir;
      SYMPHONY_PORT = toString port;
      PLAYBOOK_CODEX_BASE_URL = "https://spark-ix.tail368802.ts.net:8443";
      FORGEJO_BASE_URL = "https://git.ix.dev";
      FORGEJO_API_URL = "https://git.ix.dev/api/v1";
      FORGEJO_LOGIN = "ix";
      FORGEJO_GIT_SSH_COMMAND = "ssh -i ${forgejoSshKey} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new";
      # Enable the in-dashboard codex session viewer that landed in
      # indexable-inc/symphony#48. Without this set, /codex renders the
      # "viewer disabled" stub.
      CODEX_VIEWER_ENABLED = "1";
    };

    serviceConfig = {
      Type = "simple";
      User = username;
      Group = "users";
      WorkingDirectory = repoDir;
      EnvironmentFile = [
        config.sops.secrets."symphony.env".path
        config.sops.secrets."symphony-forgejo.env".path
        config.sops.secrets."mgrep.env".path
      ];
      Environment = "PATH=${path}";
      ExecStart = "${pkgs.nix}/bin/nix run ${repoDir} -- --i-understand-that-this-will-be-running-without-the-usual-guardrails";
      Restart = "on-failure";
      RestartSec = 10;
    };
  };

  systemd.services.symphony-update = {
    description = "Pull indexable-inc/symphony main; restart symphony.service on advance";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = [ config.sops.secrets."symphony.env".path ];
      ExecStart = "${updateScript}";
    };
  };

  systemd.timers.symphony-update = {
    description = "Poll indexable-inc/symphony main every 10 minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "3min";
      OnUnitActiveSec = "10min";
      AccuracySec = "30s";
      Unit = "symphony-update.service";
    };
  };
}
