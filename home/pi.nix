{
  lib,
  pkgs,
  hostConfig,
  ...
}:
lib.mkIf hostConfig.isLinux {
  # Install pi-coding-agent globally via npm at activation time.
  home.activation.installPiAgent = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    export PATH="${
      lib.makeBinPath [
        pkgs.nodejs_22
        pkgs.coreutils
      ]
    }:$PATH"

    npm_prefix="$(npm prefix -g 2>/dev/null)"
    pkg_dir="$npm_prefix/lib/node_modules/@mariozechner/pi-coding-agent"

    if [ ! -d "$pkg_dir" ]; then
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

    npm_prefix="$(npm prefix -g 2>/dev/null)"
    pi_bin="$npm_prefix/bin/pi"

    if [ -x "$pi_bin" ]; then
      for pkg in "@e9n/pi-channels" "pi-schedule-prompt" "pi-subagents"; do
        "$pi_bin" install "npm:$pkg" 2>/dev/null || true
      done
    fi
  '';
}
