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

  provider = "custom";
  baseUrl = "http://127.0.0.1:18080/v1";
  model = "qwen3.6-35b-a3b";

  cliToolsets = [
    "clarify"
    "code_execution"
    "cronjob"
    "file"
    "memory"
    "session_search"
    "terminal"
    "web"
  ];
  cliToolsetsOff = [
    "skills"
    "browser"
    "vision"
    "video"
    "image_gen"
    "video_gen"
    "x_search"
    "tts"
    "todo"
    "delegation"
    "homeassistant"
    "spotify"
    "yuanbao"
    "computer_use"
    "context_engine"
  ];

  pinModelConfig = pkgs.writeShellScript "hermes-pin-config" ''
    set -euo pipefail
    cfg="${hermesHome}/config.yaml"

    set_if_diff() {
      key="$1"; want="$2"
      have="null"
      if [ -f "$cfg" ]; then
        have="$(${pkgs.yq-go}/bin/yq -r ".$key // \"null\"" "$cfg" 2>/dev/null || echo null)"
      fi
      if [ "$have" != "$want" ]; then
        ${hermes}/bin/hermes config set "$key" "$want"
      fi
    }

    set_if_diff model.provider "${provider}"
    set_if_diff model.base_url "${baseUrl}"
    set_if_diff model.default "${model}"

    set_if_diff display.busy_input_mode "steer"

    set_if_diff display.platforms.photon.tool_progress "false"
    set_if_diff display.platforms.photon.streaming "false"

    set_if_diff approvals.cron_mode "approve"

    have_mem="$(${pkgs.yq-go}/bin/yq -r '.memory.provider // ""' "$cfg" 2>/dev/null || echo "")"
    if [ -n "$have_mem" ]; then
      ${hermes}/bin/hermes memory off || true
    fi

    want_tools="${toString cliToolsets}"
    want_sorted="$(printf '%s\n' $want_tools | sort | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    have_sorted="$(${pkgs.yq-go}/bin/yq -r '.platform_toolsets.cli // [] | sort | join(" ")' "$cfg" 2>/dev/null || echo "")"
    if [ "$have_sorted" != "$want_sorted" ]; then
      ${hermes}/bin/hermes tools disable ${toString cliToolsetsOff} || true
      ${hermes}/bin/hermes tools enable $want_tools || true
    fi

    rm -rf "${hermesHome}/skills" \
      "${hermesHome}/.bundled_manifest" \
      "${hermesHome}/.curator_state" \
      "${hermesHome}/.curator_backups" \
      "${hermesHome}/.skills_prompt_snapshot.json" 2>/dev/null || true
  '';
in
{
  systemd.services.hermes-gateway = {
    description = "Nous Research Hermes Agent gateway (local brain)";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "llama-cpp.service"
    ];
    wants = [
      "network-online.target"
      "llama-cpp.service"
    ];

    environment = {
      HOME = home;
      HERMES_HOME = hermesHome;
      HERMES_INFERENCE_PROVIDER = provider;
      CUSTOM_BASE_URL = baseUrl;
      HERMES_GATEWAY_BUSY_ACK_ENABLED = "false";
      HERMES_YOLO_MODE = "1";
    };

    serviceConfig = {
      Type = "simple";
      User = user;
      WorkingDirectory = home;

      ExecStartPre = pinModelConfig;
      ExecStart = "${hermes}/bin/hermes gateway";

      EnvironmentFile = config.sops.secrets."hermes-photon.env".path;

      Restart = "on-failure";
      RestartSec = 5;
      TimeoutStartSec = "300";
      OOMScoreAdjust = 500;

      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = false;
      ReadWritePaths = [ home ];
      PrivateTmp = true;
    };

    path = [
      hermes
      pkgs.bash
      pkgs.coreutils
      pkgs.git
    ];
  };

  systemd.user.tmpfiles.users.${user}.rules = [
    "d ${hermesHome} 0700 - - -"
    "L+ ${hermesHome}/SOUL.md - - - - ${repoHermesDir}/SOUL.md"
    "L+ ${hermesHome}/AGENTS.md - - - - ${repoHermesDir}/AGENTS.md"
    "L+ ${hermesHome}/TOOLS.md - - - - ${repoHermesDir}/TOOLS.md"
    "L+ ${hermesHome}/HEARTBEAT.md - - - - ${repoHermesDir}/HEARTBEAT.md"
  ];
}
