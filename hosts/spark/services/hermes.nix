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
    "computer"
  ];
  skillsDir = ../../../dots/hermes/skills;
  skillNames = lib.filter (name: builtins.pathExists (skillsDir + "/${name}/SKILL.md")) (
    lib.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir skillsDir))
  );
  skillSources = {
    hermes-agent = inputs.hermes-agent + "/skills/autonomous-ai-agents/hermes-agent";
    cua-driver = cuaDriver.skills;
    spark-computer = ../../../dots/agents/skills/spark-computer;
  }
  // lib.genAttrs skillNames (name: skillsDir + "/${name}");
  skills = pkgs.runCommand "hermes-skills" { } ''
    mkdir -p $out
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: path: "cp -rL ${path} $out/${name}") skillSources
    )}
  '';
in
{
  imports = [
    inputs.hermes-agent.nixosModules.default
    ./roommate-agent.nix
  ];

  networking.hosts."100.114.116.11" = [ "spark-ix.tail368802.ts.net" ];

  systemd.tmpfiles.rules = [
    "r ${stateDir}/.hermes/plugins/knowledge-base - - - -"
    "r ${stateDir}/workspace/kb-staging - - - -"
  ];

  system.activationScripts.hermes-skills = lib.stringAfter [ "hermes-agent-setup" ] ''
    if [ ! -e ${stateDir}/skills-before-nix ]; then
      mv ${stateDir}/.hermes/skills ${stateDir}/skills-before-nix
      chmod 0700 ${stateDir}/skills-before-nix
      install -d -o ${username} -g users -m 0700 ${stateDir}/.hermes/skills
    fi
  '';

  services.hermes-agent = {
    enable = true;
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
    extraPlugins = [
      (import ../../../pkgs/hermes-conversation {
        inherit pkgs;
      })
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
    hermesHomeFiles.".no-bundled-skills" =
      "Skills are selected by Nix in hosts/spark/services/hermes.nix.\n";
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
      delegation = {
        model = "gpt-6-astra";
        reasoning_effort = "low";
        max_spawn_depth = 1;
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
      plugins = {
        enabled = [ "conversation" ];
        disabled = [ "knowledge-base" ];
        entries.conversation.settings = {
          platforms = [ "photon" ];
          foreground_tools = [
            "delegate_task"
            "session_search"
            "memory"
            "skills_list"
            "skill_view"
            "clarify"
            "mcp__roomcast__status"
            "mcp__roomcast__control"
            "mcp__roomcast__seek"
            "mcp__roomcast__subtitles"
          ];
        };
      };
      tools.tool_search.enabled = "off";
      skills = {
        creation_nudge_interval = 0;
        external_dirs = [ "${skills}" ];
        project_discovery = false;
      };
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
    restartTriggers = config.services.hermes-agent.extraPlugins ++ [
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
