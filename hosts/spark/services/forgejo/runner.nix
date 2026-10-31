{
  config,
  pkgs,
  lib,
  ...
}:
let
  forgejoDomain = config.services.forgejo.settings.server.DOMAIN;
  runnerTokenFile = config.sops.secrets."forgejo-runner-token".path;
  runnerCacheRoot = "/var/cache/forgejo-runner";
  nixRepo = "${config.services.forgejo.repositoryRoot}/harivansh-afk/nix.git";
  sparkSwitchMain = pkgs.writeShellScript "spark-switch-main" ''
    set -euo pipefail
    dir=$(${pkgs.coreutils}/bin/mktemp -d /run/spark-deploy.XXXXXX)
    trap '${pkgs.coreutils}/bin/rm -rf "$dir"' EXIT
    ${pkgs.git}/bin/git -c safe.directory=${nixRepo} clone --quiet --branch main --single-branch ${nixRepo} "$dir/nix"
    echo "deploying main at $(${pkgs.git}/bin/git -C "$dir/nix" rev-parse HEAD)"
    /run/current-system/sw/bin/nixos-rebuild switch --flake "$dir/nix#spark"
  '';
  sparkDeploy = pkgs.writeShellApplication {
    name = "spark-deploy";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      if [ "$#" -ne 0 ]; then
        echo "spark-deploy takes no arguments; it always deploys main" >&2
        exit 2
      fi
      unit="spark-deploy-$(date +%s)"
      status=0
      systemd-run --unit="$unit" --wait --collect --quiet \
        --setenv=SUDO_UID="''${SUDO_UID:?run spark-deploy through sudo}" \
        --setenv=PATH=/run/wrappers/bin:/run/current-system/sw/bin \
        --property=TimeoutStartSec=40min \
        ${sparkSwitchMain} || status=$?
      journalctl --unit="$unit" --output=cat --no-pager
      exit "$status"
    '';
  };
in
{
  systemd.services.gitea-runner-spark = {
    restartIfChanged = false;
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = lib.mkForce "gitea-runner";
      Group = lib.mkForce "gitea-runner";
      NoNewPrivileges = lib.mkForce false;
      RestrictSUIDSGID = lib.mkForce false;
    };
  };

  users.users.gitea-runner = {
    isSystemUser = true;
    group = "gitea-runner";
    home = "/var/lib/gitea-runner";
    createHome = true;
  };
  users.groups.gitea-runner = { };

  environment.systemPackages = [ sparkDeploy ];

  security.sudo.extraRules = [
    {
      users = [ "gitea-runner" ];
      commands = [
        {
          command = "/run/current-system/sw/bin/spark-deploy \"\"";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  systemd.tmpfiles.rules = [
    "d ${runnerCacheRoot} 0750 gitea-runner gitea-runner -"
    "d ${runnerCacheRoot}/cargo 0750 gitea-runner gitea-runner -"
    "d ${runnerCacheRoot}/npm 0750 gitea-runner gitea-runner -"
    "d ${runnerCacheRoot}/pip 0750 gitea-runner gitea-runner -"
    "d ${runnerCacheRoot}/pre-commit 0750 gitea-runner gitea-runner -"
    "d ${runnerCacheRoot}/rustup 0750 gitea-runner gitea-runner -"
    "d ${runnerCacheRoot}/uv 0750 gitea-runner gitea-runner -"
    "d ${runnerCacheRoot}/actcache 0750 gitea-runner gitea-runner -"
  ];

  services.gitea-actions-runner = {
    package = pkgs.forgejo-runner;

    instances.spark = {
      enable = true;
      name = "spark";
      url = "https://${forgejoDomain}";
      tokenFile = runnerTokenFile;

      labels = [
        "native:host"
        "spark:host"
        "ubuntu-latest:docker://node:24-bookworm"
      ];

      hostPackages = with pkgs; [
        bash
        coreutils
        curl
        fd
        gh
        git
        gnumake
        gnused
        gnutar
        gzip
        gawk
        jq
        nix
        nixos-rebuild
        nodejs_24
        pkg-config
        pnpm
        python3
        python3Packages.pip
        ripgrep
        rustup
        stdenv.cc
        unzip
        uv
        wget
        xvfb-run
        xz
        zip
      ];

      settings = {
        runner = {
          capacity = 2;
          timeout = "3h";
          envs = {
            CARGO_HOME = "${runnerCacheRoot}/cargo";
            PIP_CACHE_DIR = "${runnerCacheRoot}/pip";
            PRE_COMMIT_HOME = "${runnerCacheRoot}/pre-commit";
            RUSTUP_HOME = "${runnerCacheRoot}/rustup";
            UV_CACHE_DIR = "${runnerCacheRoot}/uv";
            npm_config_cache = "${runnerCacheRoot}/npm";
          };
        };
        cache = {
          dir = "${runnerCacheRoot}/actcache";
        };
      };
    };
  };
}
