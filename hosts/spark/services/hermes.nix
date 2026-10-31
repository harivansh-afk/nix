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
  soul = ../../../dots/hermes/SOUL.md;
  skills = pkgs.runCommand "hermes-skills" { } ''
    mkdir -p $out
    cp -rL ${inputs.hermes-agent}/skills/autonomous-ai-agents/hermes-agent $out/hermes-agent
    cp -rL ${../../../dots/agents/skills/spark-computer} $out/spark-computer
    cp -rL ${inputs.mattpocock-skills}/skills/productivity/writing-for-agents $out/writing-for-agents
  '';
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
      ".no-bundled-skills" = "Skills come from hosts/spark/services/hermes.nix.\n";
    };
    documents."AGENTS.md" = agentInstructions.codex;
    backend = {
      mode = "dashboard";
      host = "127.0.0.1";
      inherit port;
    };
    settings = {
      timezone = "America/New_York";
      model = {
        provider = "codex-lb";
        default = "gpt-6.1-sol";
      };
      providers.codex-lb = {
        base_url = "http://127.0.0.1:18475/backend-api/codex";
        api_mode = "codex_responses";
        api_key = "codex-lb";
      };
      agent = {
        reasoning_effort = "medium";
        disabled_toolsets = [
          "browser"
          "computer_use"
          "image_gen"
          "tts"
          "kanban"
        ];
      };
      approvals = {
        mode = "smart";
        cron_mode = "deny";
        smart_policy = ''
          Always ESCALATE git push --force in any form, rm -rf outside the current repository or workspace, anything under /etc or /nix, systemctl changes, and any command that sends a message or spends money. Routine development inside a repository (tests, builds, uv and nix commands, git commit, git push to a feature branch, tea pr create) is safe.
        '';
      };
      skills = {
        external_dirs = [ "${skills}" ];
        create_dir = "${home}/Documents/Git/nix/dots/hermes/skills";
        write_approval = true;
        project_discovery = false;
        creation_nudge_interval = 0;
      };
      mcp_servers.beeper = {
        url = "http://127.0.0.1:23373/v0/mcp";
        auth = "oauth";
        timeout = 30;
        connect_timeout = 15;
      };
      sessions.auto_prune = true;
      dashboard.public_url = url;
    };
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
      path = [ "/etc/profiles/per-user/${username}" ];
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
