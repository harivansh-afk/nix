{
  config,
  inputs,
  lib,
  pkgs,
  username,
  ...
}:
let
  tailnet = import ../../../lib/tailnet.nix;
  agentInstructions = import ../../../lib/agent-instructions.nix { inherit pkgs; };
  user = config.users.users.${username};
  inherit (user) home;
  stateDir = "${home}/.local/state/hermes";
  port = 9119;
  url = "https://spark.${tailnet.domain}:${toString port}";
  tailscale = config.services.tailscale.package;
  ccProxy = inputs.cc-proxy.packages.${pkgs.stdenv.hostPlatform.system}.default;
  soul = ../../../dots/hermes/SOUL.md;
  # Claude Code's skills plus Hermes's own manual.
  skills = pkgs.linkFarm "hermes-skills" (
    import ../../../lib/agent-skills.nix {
      inherit pkgs;
      mattpocock = inputs.mattpocock-skills;
      spark = true;
    }
    ++ [
      {
        name = "hermes-agent";
        path = "${inputs.hermes-agent}/skills/autonomous-ai-agents/hermes-agent";
      }
    ]
  );
  # Claude Code's MCP servers. Beeper's OAuth token lives in HERMES_HOME/mcp-tokens.
  mcpServers = lib.mapAttrs (
    name: server:
    server
    // {
      connect_timeout = 20;
    }
    // lib.optionalAttrs (name == "beeper") {
      auth = "oauth";
      timeout = 60;
    }
  ) (import ../../../lib/agent-mcp.nix { inherit pkgs; }).servers;
  units = [
    "hermes-agent"
    "hermes-backend"
  ];
in
{
  imports = [ inputs.hermes-agent.nixosModules.default ];

  services.hermes-agent = {
    enable = true;
    package = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
      version = "0.22.5";
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
    ];
    environmentFiles = [ config.sops.secrets."hermes.env".path ];
    hermesHomeFiles = {
      "SOUL.md" = soul;
      "profile.yaml" = "display_name: spark\n";
      ".no-bundled-skills" = "Skills come from hosts/spark/services/hermes.nix.\n";
    };
    documents."AGENTS.md" = agentInstructions.claude;
    backend = {
      mode = "dashboard";
      host = "127.0.0.1";
      inherit port;
    };
    settings = {
      timezone = "America/New_York";
      model = {
        provider = "cc-proxy";
        default = "claude-opus-5-5";
      };
      providers = {
        codex-lb = {
          base_url = "http://127.0.0.1:18475/backend-api/codex";
          api_mode = "codex_responses";
          api_key = "codex-lb";
        };
        cc-proxy = {
          base_url = "http://127.0.0.1:18473";
          api_mode = "anthropic_messages";
          key_cmd = "${ccProxy}/bin/cc-proxy key";
        };
      };
      agent = {
        reasoning_effort = "medium";
        # Off where Claude Code has no equivalent or denies the tool (CronCreate, AskUserQuestion).
        disabled_toolsets = [
          "browser"
          "clarify"
          "computer_use"
          "cronjob"
          "image_gen"
          "tts"
          "kanban"
        ];
      };
      # Claude Code runs with bypassPermissions; match it.
      approvals.mode = "off";
      skills = {
        external_dirs = [ "${skills}" ];
        create_dir = "${home}/Documents/Git/nix/dots/hermes/skills";
        write_approval = true;
        project_discovery = false;
        creation_nudge_interval = 0;
      };
      mcp_servers = mcpServers;
      sessions.auto_prune = true;
      dashboard.public_url = url;
    };
  };

  system.activationScripts = {
    hermes-mcp-reset = lib.stringAfter [ "users" ] ''
      if [ -f ${stateDir}/.hermes/config.yaml ]; then
        ${pkgs.yq-go}/bin/yq -i 'del(.mcp_servers)' ${stateDir}/.hermes/config.yaml
      fi
    '';
    hermes-agent-setup.deps = [ "hermes-mcp-reset" ];
  };

  systemd.services =
    lib.genAttrs units (_: {
      restartTriggers = [
        (pkgs.writeText "hermes-settings.json" (builtins.toJSON config.services.hermes-agent.settings))
        soul
      ];
      after = [ "user@${toString user.uid}.service" ];
      wants = [ "user@${toString user.uid}.service" ];
      environment.HOME = lib.mkForce home;
      # Claude Code's PATH: the nix profile plus the curl-installed claude and npm codex.
      path = [
        "/etc/profiles/per-user/${username}"
        "${home}/.local"
        "${home}/.local/share/npm"
      ];
      serviceConfig = {
        ReadWritePaths = [ home ];
        UMask = lib.mkForce "0077";
      };
    })
    // {
      hermes-tailscale-serve = {
        description = "Hermes Tailscale Serve";
        after = [
          "tailscaled.service"
          "hermes-backend.service"
        ];
        requires = [
          "tailscaled.service"
          "hermes-backend.service"
        ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStartPre = "${tailscale}/bin/tailscale wait";
          ExecStart = "${tailscale}/bin/tailscale serve --bg --https=${toString port} http://127.0.0.1:${toString port}";
          ExecStop = "${tailscale}/bin/tailscale serve --https=${toString port} off";
        };
      };
    };
}
