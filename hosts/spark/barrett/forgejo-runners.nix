{
  config,
  lib,
  pkgs,
  ...
}:
let
  homeDir = config.homeDirectory;
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
  ];
  actCacheRoot = "${homeDir}/.cache/act";
  actCacheCleanupScript = pkgs.writeShellScript "forgejo-runner-act-cache-cleanup" ''
    set -eu
    if [ ! -d ${lib.escapeShellArg actCacheRoot} ]; then
      exit 0
    fi
    ${pkgs.findutils}/bin/find ${lib.escapeShellArg actCacheRoot} \
      -mindepth 1 -maxdepth 1 -type d -mtime +7 \
      -exec ${pkgs.coreutils}/bin/rm -rf {} +
  '';
  yamlFormat = pkgs.formats.yaml { };
  iniFormat = pkgs.formats.ini { listToValue = lib.concatStringsSep " "; };

  renderSystemdUnit = name: unitConfig: iniFormat.generate name unitConfig;

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
      unitFile = renderSystemdUnit "forgejo-runner-${name}.service" {
        Unit = {
          Description = "Forgejo Runner (${name})";
          Wants = [ "network-online.target" ];
          After = [ "network-online.target" ];
        };
        Service = {
          Type = "simple";
          Environment = [
            "PATH=${runnerPath}:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin"
          ];
          WorkingDirectory = stateDir;
          ExecStartPre = registerPath;
          ExecStart = daemonPath;
          Restart = "always";
          RestartSec = 2;
        };
        Install.WantedBy = [ "default.target" ];
      };
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
        unitFile
        ;
    };

  runners = map mkRunner runnerNames;

  cacheCleanupUnitFile = renderSystemdUnit "forgejo-runner-act-cache-cleanup.service" {
    Unit.Description = "Prune Forgejo runner act per-job cache entries older than 7 days";
    Service = {
      Type = "oneshot";
      ExecStart = "${actCacheCleanupScript}";
    };
  };
  cacheCleanupTimerFile = renderSystemdUnit "forgejo-runner-act-cache-cleanup.timer" {
    Unit.Description = "Daily prune of Forgejo runner act per-job cache entries older than 7 days";
    Timer = {
      OnCalendar = "daily";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };

  perRunnerFiles =
    runner:
    let
      unitName = "forgejo-runner-${runner.name}.service";
    in
    {
      ${runner.configRelPath}.source = runner.configFile;
      ${runner.registerRelPath} = {
        source = runner.registerScript;
        executable = true;
      };
      ${runner.daemonRelPath} = {
        source = runner.daemonScript;
        executable = true;
      };
      ".config/systemd/user/${unitName}".source = runner.unitFile;
      ".config/systemd/user/default.target.wants/${unitName}".source = runner.unitFile;
    };
in
{
  files = lib.mkMerge (
    (map perRunnerFiles runners)
    ++ [
      {
        ".config/systemd/user/forgejo-runner-act-cache-cleanup.service".source = cacheCleanupUnitFile;
        ".config/systemd/user/forgejo-runner-act-cache-cleanup.timer".source = cacheCleanupTimerFile;
        ".config/systemd/user/timers.target.wants/forgejo-runner-act-cache-cleanup.timer".source =
          cacheCleanupTimerFile;
      }
    ]
  );

  # Pre-create state + cache dirs for each runner.
  dirs = lib.concatMap (runner: [ runner.stateDir ] ++ runner.cacheDirs) runners;

  activationLines = ''
    # Reload systemd user units so newly written / changed unit files take effect.
    if command -v ${pkgs.systemd}/bin/systemctl >/dev/null 2>&1; then
      ${pkgs.systemd}/bin/systemctl --user daemon-reload 2>/dev/null || true
    fi
  '';
}
