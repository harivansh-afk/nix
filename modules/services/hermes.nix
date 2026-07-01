{
  config,
  inputs,
  pkgs,
  ...
}:
let
  hermes = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
    extraDependencyGroups = [ "messaging" ];
  };

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
    "file"
    "memory"
    "messaging"
    "session_search"
    "terminal"
    "web"
  ];
  cliToolsetsOff = [
    "skills"
    "browser"
    "vision"
    "image_gen"
    "tts"
    "todo"
    "delegation"
    "cronjob"
    "moa"
    "homeassistant"
    "rl"
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
    };

    serviceConfig = {
      Type = "simple";
      User = user;
      WorkingDirectory = home;

      ExecStartPre = pinModelConfig;
      ExecStart = "${hermes}/bin/hermes gateway";

      EnvironmentFile = config.sops.secrets."hermes-telegram.env".path;

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
