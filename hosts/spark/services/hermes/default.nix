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
  cuaDriver = pkgs.callPackage ../../../../pkgs/cua-driver { };
  computer = import ../../../../pkgs/computer-tools { inherit pkgs; };
  toolsets = [
    "hermes-cli"
    "computer"
    "beeper"
  ];
  skillsDir = ../../../../dots/hermes/skills;
  skillNames = lib.filter (name: builtins.pathExists (skillsDir + "/${name}/SKILL.md")) (
    lib.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir skillsDir))
  );
  skillSources = {
    hermes-agent = inputs.hermes-agent + "/skills/autonomous-ai-agents/hermes-agent";
    cua-driver = cuaDriver.skills;
    spark-computer = ../../../../dots/agents/skills/spark-computer;
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
    ./desktop.nix
    ./devin.nix
    ./imessage.nix
    ./roommates.nix
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
    package = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
      version = "0.21.5";
      distance = 5832;
    };
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
    ];
    environment = {
      HERMES_GATEWAY_BUSY_ACK_ENABLED = "false";
    };
    hermesHomeFiles."SOUL.md" = "";
    hermesHomeFiles.".no-bundled-skills" =
      "Skills are selected by Nix in hosts/spark/services/hermes/default.nix.\n";
    documents."AGENTS.md" = ../../../../dots/hermes/AGENTS.md;

    backend = {
      mode = "serve";
      host = "spark-ix.tail368802.ts.net";
      waitFor = "hostname";
    };

    settings = {
      model = {
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
        model = "qwen3.8-flash-next";
      };
      mcp_servers =
        (lib.mapAttrs (
          _: server:
          server
          // {
            timeout = 60;
            lazy = true;
          }
        ) computer.servers)
        // {
          beeper = {
            url = "http://127.0.0.1:23373/v0/mcp";
            auth = "oauth";
            oauth = {
              scope = "read write";
              cimd = false;
            };
            timeout = 30;
            connect_timeout = 15;
          };
        };
      approvals.mode = "off";
      security.protected_instruction_files = false;
      plugins = {
        enabled = [ "relay-hermes" ];
        disabled = [ "knowledge-base" ];
      };
      tools.tool_search.enabled = "auto";
      skills = {
        creation_nudge_interval = 0;
        external_dirs = [ "${skills}" ];
        project_discovery = false;
      };
      platform_toolsets = {
        cli = toolsets;
        relayapp = toolsets;
      };
      memory = {
        memory_enabled = true;
        user_profile_enabled = true;
      };
      display = {
        busy_input_mode = "interrupt";
        memory_notifications = "off";
        platforms.relayapp = {
          tool_progress = false;
          interim_assistant_messages = false;
          long_running_notifications = false;
          streaming = false;
          busy_ack_detail = false;
          tool_preview_length = 0;
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
      ../../../../dots/hermes/SOUL.md
      ../../../../dots/hermes/AGENTS.md
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
