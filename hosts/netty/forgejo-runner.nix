{
  pkgs,
  lib,
  ...
}:

let
  cacheRoot = "/var/cache/forgejo-runner";
in
{
  systemd.tmpfiles.rules = [
    "d ${cacheRoot} 0750 forgejo-runner forgejo-runner -"
    "d ${cacheRoot}/cargo 0750 forgejo-runner forgejo-runner -"
    "d ${cacheRoot}/npm 0750 forgejo-runner forgejo-runner -"
    "d ${cacheRoot}/pip 0750 forgejo-runner forgejo-runner -"
    "d ${cacheRoot}/pre-commit 0750 forgejo-runner forgejo-runner -"
    "d ${cacheRoot}/rustup 0750 forgejo-runner forgejo-runner -"
    "d ${cacheRoot}/uv 0750 forgejo-runner forgejo-runner -"
    "d ${cacheRoot}/actcache 0750 forgejo-runner forgejo-runner -"
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
        nodejs_22
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
