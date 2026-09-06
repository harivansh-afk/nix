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
  computer = import ../../../pkgs/spark-computer { inherit pkgs; };
  hermesPackage = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
    callPackage =
      path: args:
      pkgs.callPackage path (
        args
        // lib.optionalAttrs (baseNameOf path == "python.nix") {
          pythonSrc = pkgs.applyPatches {
            src = args.pythonSrc;
            patches = [ ../../../pkgs/spark-computer/hermes-mcp-images.patch ];
          };
        }
      );
  };
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
  toolsets = [
    "hermes-cli"
    "knowledge_base"
    "computer"
  ];
  skillsDir = ../../../dots/hermes/skills;
  skillNames = lib.filter (name: builtins.pathExists (skillsDir + "/${name}/SKILL.md")) (
    lib.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir skillsDir))
  );
in
{
  imports = [ inputs.hermes-agent.nixosModules.default ];

  networking.hosts."100.114.116.11" = [ "spark-ix.tail368802.ts.net" ];

  systemd.tmpfiles.rules = [
    "L+ ${stateDir}/.hermes/plugins/knowledge-base - - - - /home/rathi/Documents/Git/nix/dots/hermes/plugins/knowledge-base"
    "L+ ${stateDir}/workspace/kb-staging - - - - /var/lib/kb/staging"
    "L+ ${stateDir}/.hermes/skills/cua-driver - - - - ${cuaDriver.skills}"
    "L+ ${stateDir}/.hermes/skills/spark-computer - - - - ${../../../dots/agents/skills/spark-computer}"
  ]
  ++ map (name: "L+ ${stateDir}/.hermes/skills/${name} - - - - ${skillsDir + "/${name}"}") skillNames;

  services.hermes-agent = {
    enable = true;
    package = hermesPackage;
    user = username;
    group = "users";
    createUser = false;
    inherit stateDir;
    workingDirectory = "${stateDir}/workspace";
    addToSystemPackages = true;
    extraPackages = [
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
      PHOTON_SIDECAR_DIR = "${photonSidecar}";
      PHOTON_NODE_BIN = "${pkgs.nodejs}/bin/node";
      PHOTON_SIDECAR_PORT = "18789";
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
        disabled_toolsets = [
          "browser"
          "computer_use"
        ];
      };
      providers.spark = {
        base_url = "http://127.0.0.1:18080/v1";
        api_mode = "chat_completions";
        model = "qwen3.8-27b";
      };
      mcp_servers.computer = {
        command = "${computer}/bin/spark-computer";
        args = [ ];
        timeout = 180;
        lazy = false;
        tools.include = [
          "computer_exec"
          "computer_close"
        ];
      };
      approvals.mode = "off";
      security.protected_instruction_files = false;
      plugins.enabled = [ "knowledge-base" ];
      skills.creation_nudge_interval = 0;
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
    };
    path = [
      "/run/current-system/sw"
      "/etc/profiles/per-user/${username}"
    ];
    serviceConfig = {
      ReadWritePaths = [
        home
        runtimeDir
      ];
      UMask = lib.mkForce "0077";
    };
  });
}
