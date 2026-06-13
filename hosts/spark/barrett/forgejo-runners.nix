# Forgejo runners for forge.barrettruth.com, running as systemd user units
# under the barrett account (lingering, so they start at boot).
#
# Formerly a home-manager module; now a plain NixOS module. The unit files,
# runner configs, and wrapper scripts are nix-store files symlinked into
# barrett's home by an activation script that runs as barrett. Enablement is
# the same `.wants/` symlinks `systemctl --user enable` would create, and a
# best-effort daemon-reload/start picks up changes without waiting for a
# reboot.
{
  lib,
  pkgs,
  ...
}:
let
  username = "barrett";
  homeDir = "/home/${username}";
  cacheHome = "${homeDir}/.cache";
  configHome = "${homeDir}/.config";
  stateHome = "${homeDir}/.local/state";
  runnerEnvFile = "/run/secrets/barrett-forgejo-runner-token";
  runnerUrl = "https://forge.barrettruth.com";
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
        INSTANCE_FILE="$INSTANCE_DIR/.instance"
        LABELS_WANTED='${runnerLabelText}'
        NAME_WANTED='${name}'
        INSTANCE_WANTED='${runnerUrl}'
        LABELS_CURRENT="$(cat "$LABELS_FILE" 2>/dev/null || printf '0')"
        NAME_CURRENT="$(cat "$NAME_FILE" 2>/dev/null || printf '0')"
        INSTANCE_CURRENT="$(cat "$INSTANCE_FILE" 2>/dev/null || printf '0')"
        if [ ! -e "$INSTANCE_DIR/.runner" ] || [ "$LABELS_WANTED" != "$LABELS_CURRENT" ] || [ "$NAME_WANTED" != "$NAME_CURRENT" ] || [ "$INSTANCE_WANTED" != "$INSTANCE_CURRENT" ]; then
          rm -f "$INSTANCE_DIR/.runner"
          "$RUNNER_BIN" register --no-interactive \
            --instance ${lib.escapeShellArg runnerUrl} \
            --token "$TOKEN" \
            --name ${lib.escapeShellArg name} \
            --labels ${lib.escapeShellArg runnerLabelCsv} \
            --config "$CONFIG_FILE"
          printf '%s\n' "$LABELS_WANTED" > "$LABELS_FILE"
          printf '%s\n' "$NAME_WANTED" > "$NAME_FILE"
          printf '%s\n' "$INSTANCE_WANTED" > "$INSTANCE_FILE"
        fi
      '';
      daemonScript = pkgs.writeShellScript "forgejo-runner-${name}-daemon" ''
        set -eu
        INSTANCE_DIR="${stateDir}"
        cd "$INSTANCE_DIR"
        exec "${pkgs.forgejo-runner}/bin/act_runner" daemon --config "${configPath}"
      '';
      unitFile = pkgs.writeText "forgejo-runner-${name}.service" ''
        [Unit]
        Description=Forgejo Runner (${name})
        Wants=network-online.target
        After=network-online.target

        [Service]
        Type=simple
        Environment=PATH=${runnerPath}:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin
        WorkingDirectory=${stateDir}
        ExecStartPre=${registerPath}
        ExecStart=${daemonPath}
        Restart=always
        RestartSec=2

        [Install]
        WantedBy=default.target
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
        configPath
        daemonScript
        daemonPath
        registerScript
        registerPath
        stateDir
        unitFile
        ;
      serviceName = "forgejo-runner-${name}.service";
    };

  runners = map mkRunner runnerNames;

  cleanupServiceUnit = pkgs.writeText "forgejo-runner-act-cache-cleanup.service" ''
    [Unit]
    Description=Prune Forgejo runner act per-job cache entries older than 7 days

    [Service]
    Type=oneshot
    ExecStart=${actCacheCleanupScript}
  '';

  cleanupTimerUnit = pkgs.writeText "forgejo-runner-act-cache-cleanup.timer" ''
    [Unit]
    Description=Daily prune of Forgejo runner act per-job cache entries older than 7 days

    [Timer]
    OnCalendar=daily
    Persistent=true

    [Install]
    WantedBy=timers.target
  '';

  userUnitDir = "${configHome}/systemd/user";

  setupScript = pkgs.writeShellScript "barrett-forgejo-runners-setup" ''
    set -eu
    PATH=${pkgs.coreutils}/bin:$PATH

    mkdir -p \
      "${userUnitDir}/default.target.wants" \
      "${userUnitDir}/timers.target.wants" \
      "${homeDir}/.local/bin" \
      ${lib.concatMapStringsSep " \\\n  " (
        runner:
        lib.concatMapStringsSep " \\\n  " (dir: ''"${dir}"'') (
          runner.cacheDirs
          ++ [
            runner.stateDir
            (builtins.dirOf runner.configPath)
          ]
        )
      ) runners}

    ${lib.concatMapStringsSep "\n" (runner: ''
      ln -sfn "${runner.configFile}" "${runner.configPath}"
      ln -sfn "${runner.registerScript}" "${runner.registerPath}"
      ln -sfn "${runner.daemonScript}" "${runner.daemonPath}"
      ln -sfn "${runner.unitFile}" "${userUnitDir}/${runner.serviceName}"
      ln -sfn "${runner.unitFile}" "${userUnitDir}/default.target.wants/${runner.serviceName}"
    '') runners}

    ln -sfn "${cleanupServiceUnit}" "${userUnitDir}/forgejo-runner-act-cache-cleanup.service"
    ln -sfn "${cleanupTimerUnit}" "${userUnitDir}/forgejo-runner-act-cache-cleanup.timer"
    ln -sfn "${cleanupTimerUnit}" "${userUnitDir}/timers.target.wants/forgejo-runner-act-cache-cleanup.timer"

    # Pick up unit changes in the running user manager (linger keeps it
    # alive). Best-effort: at boot the units start via the wants symlinks.
    runtime_dir="/run/user/$(id -u)"
    if [ -d "$runtime_dir" ]; then
      export XDG_RUNTIME_DIR="$runtime_dir"
      export DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus"
      ${pkgs.systemd}/bin/systemctl --user daemon-reload || true
      ${lib.concatMapStringsSep "\n  " (
        runner: ''${pkgs.systemd}/bin/systemctl --user start "${runner.serviceName}" || true''
      ) runners}
      ${pkgs.systemd}/bin/systemctl --user start forgejo-runner-act-cache-cleanup.timer || true
    fi
  '';
in
{
  system.activationScripts.barrettForgejoRunners = {
    deps = [
      "users"
      "groups"
    ];
    text = ''
      ${pkgs.util-linux}/bin/runuser -u ${username} -- ${setupScript} \
        || echo "warning: barrett forgejo runner setup failed" >&2
    '';
  };
}
