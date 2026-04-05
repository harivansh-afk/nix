{
  pkgs,
  lib,
  ...
}:

let
  cacheRoot = "/var/cache/github-runner";

  sanitize =
    repo:
    lib.toLower (
      lib.replaceStrings
        [ "." ]
        [ "-" ]
        repo
    );

  repos = [
    "nix"
    "deskctl"
    "betterNAS"
  ];

  workDir = repo: "/var/lib/github-runner/work/${repo}";

  cacheDirs = [
    "${cacheRoot}/cargo"
    "${cacheRoot}/npm"
    "${cacheRoot}/pip"
    "${cacheRoot}/pre-commit"
    "${cacheRoot}/rustup"
    "${cacheRoot}/uv"
    "${cacheRoot}/xdg-cache"
    "${cacheRoot}/xdg-data"
  ];

  mkRunner =
    repo:
    let
      runnerId = sanitize repo;
    in
    lib.nameValuePair runnerId {
      enable = true;
      url = "https://github.com/harivansh-afk/${repo}";
      tokenFile = "/etc/github-runner/token";
      tokenType = "access";
      name = "netty-${runnerId}";
      replace = true;
      user = "github-runner";
      group = "github-runner";
      workDir = workDir repo;
      extraLabels = [
        "netty"
        "nix"
        "cache"
      ];
      extraPackages = with pkgs; [
        curl
        fd
        gh
        gnumake
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
        libx11
        libx11.dev
        libxtst
        xvfb-run
        xz
        zip
      ];
      extraEnvironment = {
        CARGO_HOME = "${cacheRoot}/cargo";
        PIP_CACHE_DIR = "${cacheRoot}/pip";
        PRE_COMMIT_HOME = "${cacheRoot}/pre-commit";
        RUSTUP_HOME = "${cacheRoot}/rustup";
        UV_CACHE_DIR = "${cacheRoot}/uv";
        XDG_CACHE_HOME = "${cacheRoot}/xdg-cache";
        XDG_DATA_HOME = "${cacheRoot}/xdg-data";
        npm_config_cache = "${cacheRoot}/npm";
      };
      serviceOverrides = {
        IOSchedulingClass = "best-effort";
        IOSchedulingPriority = 7;
        Nice = 10;
        ReadWritePaths = [ cacheRoot ];
      };
    };
in
{
  users.users.github-runner = {
    isSystemUser = true;
    group = "github-runner";
    home = "/var/lib/github-runner";
  };

  users.groups.github-runner = { };

  nix.settings.trusted-users = [ "github-runner" ];

  systemd.tmpfiles.rules =
    [
      "d /etc/github-runner 0750 root root -"
      "d /var/cache/github-runner 0750 github-runner github-runner -"
      "d /var/lib/github-runner 0750 github-runner github-runner -"
      "d /var/lib/github-runner/work 0750 github-runner github-runner -"
    ]
    ++ map (dir: "d ${dir} 0750 github-runner github-runner -") cacheDirs
    ++ map (repo: "d ${workDir repo} 0750 github-runner github-runner -") repos;

  services.github-runners = lib.listToAttrs (map mkRunner repos);
}
