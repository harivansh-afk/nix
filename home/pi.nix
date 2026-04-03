{
  config,
  lib,
  pkgs,
  hostConfig,
  ...
}:
let
  npmDir = "${config.xdg.dataHome}/npm";
  piBin = "${npmDir}/bin/pi";
in
lib.mkIf hostConfig.isLinux {
  home.file.".pi/agent/SYSTEM.md".source = ../config/pi/SYSTEM.md;
  # Install pi-coding-agent globally via npm at activation time.
  home.activation.installPiAgent = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    export PATH="${
      lib.makeBinPath [
        pkgs.nodejs_22
        pkgs.coreutils
      ]
    }:$PATH"
    export NPM_CONFIG_USERCONFIG="${config.xdg.configHome}/npm/npmrc"
    export XDG_DATA_HOME="${config.xdg.dataHome}"
    export XDG_CACHE_HOME="${config.xdg.cacheHome}"

    if [ ! -d "${npmDir}/lib/node_modules/@mariozechner/pi-coding-agent" ]; then
      npm install -g @mariozechner/pi-coding-agent 2>/dev/null || true
    fi
  '';

  # Install Pi extensions at activation time:
  #   - @e9n/pi-channels: Telegram/Slack bridge with RPC-based persistent sessions
  #   - pi-schedule-prompt: cron/interval scheduled prompts
  #   - pi-subagents: background task delegation with async execution
  home.activation.installPiExtensions = lib.hm.dag.entryAfter [ "installPiAgent" ] ''
    export PATH="${
      lib.makeBinPath [
        pkgs.nodejs_22
        pkgs.coreutils
        pkgs.git
      ]
    }:$PATH"
    export NPM_CONFIG_USERCONFIG="${config.xdg.configHome}/npm/npmrc"
    export XDG_DATA_HOME="${config.xdg.dataHome}"
    export XDG_CACHE_HOME="${config.xdg.cacheHome}"

    if [ -x "${piBin}" ]; then
      for pkg in "@e9n/pi-channels" "pi-schedule-prompt" "pi-subagents"; do
        "${piBin}" install "npm:$pkg" 2>/dev/null || true
      done
    fi
  '';
}
