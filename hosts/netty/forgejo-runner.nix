{
  pkgs,
  lib,
  ...
}:

let
  # Cache root for tooling used inside CI jobs (npm, pip, cargo, ...).
  cacheRoot = "/var/cache/forgejo-runner";
in
{
  systemd.services.gitea-runner-netty.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = lib.mkForce "gitea-runner";
    Group = lib.mkForce "gitea-runner";
    NoNewPrivileges = lib.mkForce false;
    RestrictSUIDSGID = lib.mkForce false;
  };

  users.users.gitea-runner = {
    isSystemUser = true;
    group = "gitea-runner";
    home = "/var/lib/gitea-runner";
    createHome = true;
  };
  users.groups.gitea-runner = { };

  security.sudo.extraRules = [
    {
      users = [ "gitea-runner" ];
      commands = [
        {
          command = "/run/current-system/sw/bin/nixos-rebuild";
          options = [
            "NOPASSWD"
            "SETENV"
          ];
        }
      ];
    }
  ];

  systemd.tmpfiles.rules = [
    "d ${cacheRoot} 0750 gitea-runner gitea-runner -"
    "d ${cacheRoot}/cargo 0750 gitea-runner gitea-runner -"
    "d ${cacheRoot}/npm 0750 gitea-runner gitea-runner -"
    "d ${cacheRoot}/pip 0750 gitea-runner gitea-runner -"
    "d ${cacheRoot}/pre-commit 0750 gitea-runner gitea-runner -"
    "d ${cacheRoot}/rustup 0750 gitea-runner gitea-runner -"
    "d ${cacheRoot}/uv 0750 gitea-runner gitea-runner -"
    "d ${cacheRoot}/actcache 0750 gitea-runner gitea-runner -"
  ];

  services.gitea-actions-runner = {
    package = pkgs.forgejo-runner;

    instances.netty = {
      enable = true;
      name = "netty";
      url = "https://git.harivan.sh";
      tokenFile = "/etc/forgejo-runner/token";

      labels = [
        "native:host"
        "ubuntu-latest:docker://node:20-bookworm"
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
        gawk
        jq
        nix
        nixos-rebuild
        nodejs_22
        pkg-config
        pnpm
        python3
        python3Packages.pip
        ripgrep
        rustup
        stdenv.cc
        sudo
        unzip
        uv
        wget
        xz
        zip
      ];

      settings = {
        log.level = "info";
        runner = {
          capacity = 2;
          timeout = "3h";
          envs = {
            CARGO_HOME = "${cacheRoot}/cargo";
            PIP_CACHE_DIR = "${cacheRoot}/pip";
            PRE_COMMIT_HOME = "${cacheRoot}/pre-commit";
            RUSTUP_HOME = "${cacheRoot}/rustup";
            UV_CACHE_DIR = "${cacheRoot}/uv";
            npm_config_cache = "${cacheRoot}/npm";
          };
        };
        cache = {
          enabled = true;
          dir = "${cacheRoot}/actcache";
        };
      };
    };
  };
}
