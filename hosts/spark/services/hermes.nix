{
  config,
  inputs,
  lib,
  pkgs,
  username,
  ...
}:
let
  home = config.users.users.${username}.home;
  stateDir = "${home}/.local/state/hermes";
  runtimeDir = "/run/user/${toString config.users.users.${username}.uid}";
  cuaDriver = pkgs.callPackage ../../../pkgs/cua-driver { };
  browserUse = import ../../../pkgs/browser-use { inherit pkgs inputs; };
  photonSrc = "${inputs.hermes-agent}/plugins/platforms/photon/sidecar";
  photonDeps = pkgs.importNpmLock.buildNodeModules {
    npmRoot = photonSrc;
    inherit (pkgs) nodejs;
    derivationArgs.postPatch = ''
      cp ${photonSrc}/patch-spectrum-mixed-attachments.mjs .
    '';
  };
  photonSidecar = pkgs.runCommand "hermes-photon-sidecar" { } ''
    mkdir -p $out
    cp ${photonSrc}/* $out/
    ln -s ${photonDeps}/node_modules $out/node_modules
  '';
  desktopEnv = pkgs.writeShellApplication {
    name = "hermes-desktop-env";
    runtimeInputs = [
      pkgs.systemd
      pkgs.coreutils
      pkgs.gnused
    ];
    text = builtins.readFile ./hermes-desktop-env.sh;
  };
  toolsets = [
    "hermes-cli"
    "knowledge_base"
  ];
in
{
  imports = [ inputs.hermes-agent.nixosModules.default ];

  networking.hosts."100.114.116.11" = [ "spark-ix.tail368802.ts.net" ];

  systemd.tmpfiles.rules = [
    "L+ ${stateDir}/.hermes/plugins/knowledge-base - - - - /home/rathi/Documents/Git/nix/dots/hermes/plugins/knowledge-base"
    "L+ ${stateDir}/workspace/kb-staging - - - - /var/lib/kb/staging"
    "L+ ${stateDir}/.hermes/skills/cua-driver - - - - ${cuaDriver.skills}"
    "L+ ${stateDir}/.hermes/skills/self-evolve - - - - ${../../../dots/hermes/skills/self-evolve}"
  ];

  services.hermes-agent = {
    enable = true;
    user = username;
    group = "users";
    createUser = false;
    inherit stateDir;
    workingDirectory = "${stateDir}/workspace";
    addToSystemPackages = true;
    extraPackages = [
      cuaDriver
      browserUse
      pkgs.agent-browser
      pkgs.uv
      pkgs.tea
      pkgs.jq
      pkgs.xdg-utils
    ];
    environmentFiles = [
      config.sops.secrets."anthropic.env".path
      config.sops.secrets."hermes-dashboard.env".path
      config.sops.secrets."hermes-photon.env".path
    ];
    environment = {
      HERMES_CUA_DRIVER_CMD = "${cuaDriver}/bin/cua-driver";
      PHOTON_SIDECAR_DIR = "${photonSidecar}";
      PHOTON_NODE_BIN = "${pkgs.nodejs}/bin/node";
      PHOTON_SIDECAR_PORT = "18789";
      CUA_DRIVER_RS_TELEMETRY_ENABLED = "0";
      ANONYMIZED_TELEMETRY = "false";
      HERMES_GATEWAY_BUSY_ACK_ENABLED = "false";
    };
    hermesHomeFiles."SOUL.md" = ../../../dots/hermes/SOUL.md;
    documents."AGENTS.md" = ../../../dots/hermes/AGENTS.md;

    backend = {
      mode = "serve";
      host = "spark-ix.tail368802.ts.net";
      waitFor = "hostname";
    };

    settings = {
      model = {
        provider = "openai-codex";
        default = "gpt-6-astra";
        api_mode = "codex_responses";
        base_url = "";
      };
      agent = {
        reasoning_effort = "medium";
        disabled_toolsets = [ ];
      };
      providers.spark = {
        base_url = "http://127.0.0.1:18080/v1";
        api_mode = "chat_completions";
        model = "qwen3.8-27b";
      };
      browser = {
        cloud_provider = "local";
        backend = "browser-use";
        use_real_profile = true;
        real_profile_pin = "Default";
        headed = true;
      };
      computer_use.native_wayland = true;
      approvals.mode = "smart";
      plugins.enabled = [ "knowledge-base" ];
      platform_toolsets = {
        cli = toolsets;
        photon = toolsets;
      };
      memory = {
        memory_enabled = true;
        user_profile_enabled = true;
      };
      display = {
        busy_input_mode = "steer";
        memory_notifications = "off";
        platforms.photon = {
          tool_progress = false;
          streaming = false;
        };
      };
      session_reset = {
        mode = "none";
        notify = false;
      };
    };
  };

  systemd.services = lib.genAttrs [ "hermes-agent" "hermes-backend" ] (_: {
    restartTriggers = [
      (pkgs.writeText "hermes-settings.json" (builtins.toJSON config.services.hermes-agent.settings))
      ../../../dots/hermes/SOUL.md
      ../../../dots/hermes/AGENTS.md
      config.sops.secrets."hermes-photon.env".sopsFile
    ];
    after = [ "user@${toString config.users.users.${username}.uid}.service" ];
    wants = [ "user@${toString config.users.users.${username}.uid}.service" ];
    environment = {
      HOME = lib.mkForce home;
      XDG_CONFIG_HOME = "${home}/.config";
      XDG_RUNTIME_DIR = runtimeDir;
      DBUS_SESSION_BUS_ADDRESS = "unix:path=${runtimeDir}/bus";
      XDG_SESSION_TYPE = "wayland";
      XDG_CURRENT_DESKTOP = "sway";
      GTK_A11Y = "always";
    };
    path = [
      "/run/current-system/sw"
      "/etc/profiles/per-user/${username}"
    ];
    serviceConfig = {
      ExecStartPre = "${desktopEnv}/bin/hermes-desktop-env";
      EnvironmentFile = "-${stateDir}/.hermes/desktop.env";
      ReadWritePaths = [
        home
        runtimeDir
      ];
      UMask = lib.mkForce "0077";
    };
  });
}
