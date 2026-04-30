{
  config,
  lib,
  pkgs,
  ...
}:
let
  homeDir = config.home.homeDirectory;
  cacheHome = config.xdg.cacheHome;
  configHome = config.xdg.configHome;
  stateHome = config.xdg.stateHome;
  runnerEnvFile = "/run/secrets/barrett-forgejo-runner-token";
  runnerUrl = "https://git.barrettruth.com";
  runnerPackages = with pkgs; [
    bash
    coreutils
    curl
    fd
    findutils
    gh
    git
    gnugrep
    gnumake
    gnused
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
    xz
    zip
  ];
  runnerPath = lib.makeBinPath runnerPackages;
  runnerLabels = [
    "nix:host"
    "spark:host"
    "ubuntu-latest:host"
  ];
  yamlFormat = pkgs.formats.yaml { };
  runnerNames = [
    "spark-nix-1"
    "spark-nix-2"
    "spark-nix-3"
    "spark-nix-4"
  ];
  runnerLabelText = lib.concatStringsSep "\n" runnerLabels;
  runnerLabelCsv = lib.concatStringsSep "," runnerLabels;

  mkRunner =
    name:
    let
      cacheRoot = "${cacheHome}/forgejo-runner/${name}";
      stateDir = "${stateHome}/forgejo-runner/${name}";
      configRelPath = "forgejo-runner/${name}/config.yaml";
      configPath = "${configHome}/${configRelPath}";
      registerRelPath = ".local/bin/forgejo-runner-${name}-register";
      daemonRelPath = ".local/bin/forgejo-runner-${name}-daemon";
      registerPath = "${homeDir}/${registerRelPath}";
      daemonPath = "${homeDir}/${daemonRelPath}";
      configFile = yamlFormat.generate "forgejo-runner-${name}.yaml" {
        cache = {
          dir = "${cacheRoot}/actcache";
          enabled = true;
        };
        log.level = "info";
        runner = {
          capacity = 1;
          envs = {
            CARGO_HOME = "${cacheRoot}/cargo";
            PIP_CACHE_DIR = "${cacheRoot}/pip";
            PRE_COMMIT_HOME = "${cacheRoot}/pre-commit";
            RUSTUP_HOME = "${cacheRoot}/rustup";
            UV_CACHE_DIR = "${cacheRoot}/uv";
            npm_config_cache = "${cacheRoot}/npm";
          };
          timeout = "30m";
        };
      };
      registerScript = pkgs.writeShellScript "forgejo-runner-${name}-register" ''
        set -eu
        if [ ! -r "${runnerEnvFile}" ]; then
          printf 'missing runner token env file: %s\n' "${runnerEnvFile}" >&2
          exit 1
        fi
        set -a
        . "${runnerEnvFile}"
        set +a
        : "''${TOKEN:?missing TOKEN in runner env file}"
        INSTANCE_DIR="${stateDir}"
        CONFIG_FILE="${configPath}"
        RUNNER_BIN="${pkgs.forgejo-runner}/bin/act_runner"
        mkdir -p "$INSTANCE_DIR"
        cd "$INSTANCE_DIR"
        LABELS_FILE="$INSTANCE_DIR/.labels"
        NAME_FILE="$INSTANCE_DIR/.name"
        LABELS_WANTED='${runnerLabelText}'
        NAME_WANTED='${name}'
        LABELS_CURRENT="$(cat "$LABELS_FILE" 2>/dev/null || printf '0')"
        NAME_CURRENT="$(cat "$NAME_FILE" 2>/dev/null || printf '0')"
        if [ ! -e "$INSTANCE_DIR/.runner" ] || [ "$LABELS_WANTED" != "$LABELS_CURRENT" ] || [ "$NAME_WANTED" != "$NAME_CURRENT" ]; then
          rm -f "$INSTANCE_DIR/.runner"
          "$RUNNER_BIN" register --no-interactive \
            --instance ${lib.escapeShellArg runnerUrl} \
            --token "$TOKEN" \
            --name ${lib.escapeShellArg name} \
            --labels ${lib.escapeShellArg runnerLabelCsv} \
            --config "$CONFIG_FILE"
          printf '%s\n' "$LABELS_WANTED" > "$LABELS_FILE"
          printf '%s\n' "$NAME_WANTED" > "$NAME_FILE"
        fi
      '';
      daemonScript = pkgs.writeShellScript "forgejo-runner-${name}-daemon" ''
        set -eu
        INSTANCE_DIR="${stateDir}"
        cd "$INSTANCE_DIR"
        exec "${pkgs.forgejo-runner}/bin/act_runner" daemon --config "${configPath}"
      '';
      cacheDirs = [
        cacheRoot
        "${cacheRoot}/actcache"
        "${cacheRoot}/cargo"
        "${cacheRoot}/npm"
        "${cacheRoot}/pip"
        "${cacheRoot}/pre-commit"
        "${cacheRoot}/rustup"
        "${cacheRoot}/uv"
      ];
    in
    {
      inherit
        name
        cacheDirs
        configFile
        configRelPath
        daemonScript
        daemonPath
        daemonRelPath
        registerScript
        registerPath
        registerRelPath
        stateDir
        ;
    };

  runners = map mkRunner runnerNames;
in
{
  xdg.configFile = lib.listToAttrs (
    map (runner: lib.nameValuePair runner.configRelPath { source = runner.configFile; }) runners
  );

  home.file = lib.listToAttrs (
    lib.concatMap (runner: [
      (lib.nameValuePair runner.registerRelPath { source = runner.registerScript; })
      (lib.nameValuePair runner.daemonRelPath { source = runner.daemonScript; })
    ]) runners
  );

  home.activation.ensureForgejoRunnerDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] (
    lib.concatLines (
      lib.concatMap (
        runner:
        [ "mkdir -p ${lib.escapeShellArg runner.stateDir}" ]
        ++ map (dir: "mkdir -p ${lib.escapeShellArg dir}") runner.cacheDirs
      ) runners
    )
  );

  systemd.user.services = lib.listToAttrs (
    map (
      runner:
      lib.nameValuePair "forgejo-runner-${runner.name}" {
        Unit = {
          Description = "Forgejo Runner (${runner.name})";
          Wants = [ "network-online.target" ];
          After = [ "network-online.target" ];
        };
        Service = {
          Type = "simple";
          Environment = [
            "PATH=${runnerPath}:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin"
          ];
          WorkingDirectory = runner.stateDir;
          ExecStartPre = runner.registerPath;
          ExecStart = runner.daemonPath;
          Restart = "on-failure";
          RestartSec = 2;
        };
        Install.WantedBy = [ "default.target" ];
      }
    ) runners
  );
}
