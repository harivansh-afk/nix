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
    ln -s /home/${username}/.local/share/npm/bin/gt $out/bin/gt
    ln -s /home/${username}/.local/share/npm/bin/graphite $out/bin/graphite
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
    };

    serviceConfig = {
      Type = "simple";
      User = username;
      Group = "users";
      WorkingDirectory = repoDir;
      EnvironmentFile = [
        config.sops.secrets."symphony.env".path
        config.sops.secrets."graphite.env".path
        config.sops.secrets."mgrep.env".path
      ];
      Environment = "PATH=${path}";
      ExecStart = "${pkgs.nix}/bin/nix run ${repoDir} -- --i-understand-that-this-will-be-running-without-the-usual-guardrails";
      Restart = "on-failure";
      RestartSec = 10;
    };
  };
}
