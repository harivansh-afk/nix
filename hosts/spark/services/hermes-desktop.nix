{
  config,
  lib,
  pkgs,
  ...
}:
let
  hermes = config.services.hermes-agent;
  profileHome = "${hermes.stateDir}/.hermes/profiles/desktop";
  skills = builtins.head hermes.settings.skills.external_dirs;
in
{
  systemd.tmpfiles.rules = map (dir: "d ${dir} 0700 ${hermes.user} ${hermes.group} - -") (
    [ profileHome ]
    ++ map (dir: "${profileHome}/${dir}") [
      "cron"
      "sessions"
      "logs"
      "memories"
      "skills"
      "workspace"
    ]
  );

  services.hermes-agent = {
    hermesHomeFiles = {
      "profiles/desktop/config.yaml" = builtins.toJSON {
        inherit (hermes.settings) model providers approvals;
        agent = {
          inherit (hermes.settings.agent) reasoning_effort disabled_toolsets;
        };
        delegation = {
          inherit (hermes.settings.delegation) model reasoning_effort max_spawn_depth;
        };
        display.busy_input_mode = "steer";
        terminal.cwd = "${profileHome}/workspace";
        desktop.repo_scan_roots = [ "${config.users.users.${hermes.user}.home}/Documents/Git" ];
        platform_toolsets.cli = [
          "hermes-cli"
          "computer"
        ];
        mcp_servers.computer = hermes.settings.mcp_servers.computer;
        plugins = {
          enabled = [ ];
          disabled = [
            "conversation"
            "knowledge-base"
          ];
        };
        tools.tool_search.enabled = "auto";
        skills = {
          creation_nudge_interval = 0;
          project_discovery = false;
          external_dirs = map (name: "${skills}/${name}") [
            "hermes-agent"
            "cua-driver"
            "spark-computer"
            "self-evolve"
          ];
        };
        memory = {
          memory_enabled = true;
          user_profile_enabled = true;
        };
      };
      "profiles/desktop/.env" = "";
      "profiles/desktop/.managed" = "nixos\n";
      "profiles/desktop/.no-bundled-skills" = "Skills are selected by Nix.\n";
      "profiles/desktop/SOUL.md" = "";
      "profiles/desktop/workspace/AGENTS.md" = ../../../dots/hermes/desktop/AGENTS.md;
    };
  };

  systemd.services.hermes-backend = {
    after = [ "hermes-agent.service" ];
    environment.HERMES_HOME = lib.mkForce profileHome;
    serviceConfig = {
      WorkingDirectory = lib.mkForce "${profileHome}/workspace";
      EnvironmentFile = [ config.sops.secrets."hermes-dashboard.env".path ];
    };
    restartTriggers = [
      (pkgs.writeText "hermes-desktop-config.json" hermes.hermesHomeFiles."profiles/desktop/config.yaml")
      ../../../dots/hermes/desktop/AGENTS.md
      config.sops.secrets."hermes-dashboard.env".sopsFile
    ];
  };
}
