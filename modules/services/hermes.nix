{
  config,
  inputs,
  pkgs,
  ...
}:
let
  hermesBase = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
    extraDependencyGroups = [ "messaging" ];
  };

  photonSidecarSrc = "${inputs.hermes-agent}/plugins/platforms/photon/sidecar";

  photonSidecarDeps = pkgs.importNpmLock.buildNodeModules {
    npmRoot = photonSidecarSrc;
    nodejs = pkgs.nodejs_22;
    derivationArgs = {
      postPatch = ''
        cp ${photonSidecarSrc}/patch-spectrum-mixed-attachments.mjs .
      '';
    };
  };

  hermes = hermesBase.overrideAttrs (prev: {
    postInstall = (prev.postInstall or "") + ''
      rm "$out/share/hermes-agent/plugins"
      cp -R ${inputs.hermes-agent}/plugins "$out/share/hermes-agent/plugins"
      photon=$out/share/hermes-agent/plugins/platforms/photon
      chmod u+w "$photon" "$photon/sidecar" "$photon/adapter.py"
      ln -s ${photonSidecarDeps}/node_modules "$photon/sidecar/node_modules"
      patch "$photon/adapter.py" ${./photon-multi-bubble.patch}
    '';
  });

  user = "rathi";
  home = "/home/${user}";
  hermesHome = "${home}/.hermes";

  repoHermesDir = "${home}/Documents/Git/nix/dots/hermes";

  toolsets = [
    "all"
    "kanban"
    "knowledge_base"
  ];

  hermesSettings = {
    model = {
      provider = "openai-codex";
      default = "gpt-5.6-sol";
      base_url = "";
      api_mode = "codex_responses";
    };
    agent = {
      reasoning_effort = "medium";
      disabled_toolsets = [ ];
    };
    approvals.mode = "smart";
    # Cron gather/relay scripts drive a headless browser at worst (x-feed-scan).
    cron.script_timeout_seconds = 300;
    curator = {
      enabled = true;
      consolidate = true;
      prune_builtins = false;
    };
    display = {
      busy_input_mode = "steer";
      platforms.photon = {
        tool_progress = false;
        streaming = false;
      };
    };
    memory = {
      memory_enabled = true;
      user_profile_enabled = true;
      provider = "";
      write_approval = false;
    };
    platform_toolsets = {
      cli = toolsets;
      photon = toolsets;
    };
    plugins.enabled = [ "knowledge-base" ];
    skills = {
      guard_agent_created = true;
      write_approval = false;
    };
    terminal.cwd = home;
  };

  generatedConfig = pkgs.writeText "hermes-config.json" (builtins.toJSON hermesSettings);
  mergeConfig = pkgs.callPackage "${inputs.hermes-agent}/nix/configMergeScript.nix" { };
in
{
  systemd.services.hermes-gateway = {
    description = "Nous Research Hermes Agent gateway";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    environment = {
      HOME = home;
      HERMES_HOME = hermesHome;
      HERMES_GATEWAY_BUSY_ACK_ENABLED = "false";
    };

    serviceConfig = {
      Type = "simple";
      User = user;
      WorkingDirectory = home;

      ExecStartPre = "${mergeConfig} ${generatedConfig} ${hermesHome}/config.yaml";
      ExecStart = "${hermes}/bin/hermes gateway";

      EnvironmentFile = config.sops.secrets."hermes-photon.env".path;

      Restart = "on-failure";
      RestartSec = 5;
      TimeoutStartSec = "300";
      OOMScoreAdjust = 500;

      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = false;
      ReadWritePaths = [
        home
        # Cron jobs run in this process (in-process scheduler). The loops
        # namespace takes the agent's KB notes and the finance relay marker;
        # /var/lib/loops takes scanner state (dep-release last-seen tags);
        # the saved namespace takes read-it-later notes.
        "/var/lib/kb/staging/loops"
        "/var/lib/kb/staging/saved"
        "/var/lib/loops"
      ];
      InaccessiblePaths = [
        "-/var/lib/kb/staging/finance"
        "-${home}/Documents/Downloads/security"
        "-${home}/Documents/Downloads/documents/finance-tax"
        "-${home}/Documents/Downloads/documents/travel-identity"
        "-${home}/Documents/Downloads/documents/legal-business"
      ];
      PrivateTmp = true;
    };

    path = [
      hermes
      pkgs.bash
      pkgs.coreutils
      pkgs.git
    ];
  };

  # read-it-later files into staging/saved (kb-ingestion owns the staging root).
  systemd.tmpfiles.rules = [
    "d /var/lib/kb/staging/saved 0755 ${user} users -"
  ];

  systemd.user.tmpfiles.users.${user}.rules = [
    "d ${hermesHome} 0700 - - -"
    "d ${hermesHome}/plugins 0700 - - -"
    "d ${hermesHome}/skills 0700 - - -"
    "L+ ${hermesHome}/SOUL.md - - - - ${repoHermesDir}/SOUL.md"
    "L+ ${hermesHome}/AGENTS.md - - - - ${repoHermesDir}/AGENTS.md"
    "L+ ${hermesHome}/TOOLS.md - - - - ${repoHermesDir}/TOOLS.md"
    "L+ ${hermesHome}/HEARTBEAT.md - - - - ${repoHermesDir}/HEARTBEAT.md"
    "L+ ${hermesHome}/plugins/knowledge-base - - - - ${repoHermesDir}/plugins/knowledge-base"
    "L+ ${hermesHome}/skills/feed-triage - - - - ${repoHermesDir}/skills/feed-triage"
    "L+ ${hermesHome}/skills/finance-relay - - - - ${repoHermesDir}/skills/finance-relay"
    "L+ ${hermesHome}/skills/read-it-later - - - - ${repoHermesDir}/skills/note-taking/read-it-later"
    "r! ${hermesHome}/skills/ix-morning-brief"
  ];
}
