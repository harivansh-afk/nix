{
  config,
  lib,
  pkgs,
  hostConfig,
  ...
}:
lib.mkIf (!hostConfig.isDarwin) {
  # agent-browser user-level config: point at nix chromium, run headless
  home.file.".agent-browser/config.json".text = builtins.toJSON {
    executablePath = "${pkgs.chromium}/bin/chromium";
    args = "--no-sandbox,--disable-gpu,--disable-dev-shm-usage";
  };

  # Install agent-browser globally via npm at activation time
  home.activation.installAgentBrowser = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    export PATH="${
      lib.makeBinPath [
        pkgs.nodejs_22
        pkgs.coreutils
      ]
    }:$PATH"

    if ! command -v agent-browser >/dev/null 2>&1; then
      npm install -g agent-browser 2>/dev/null || true
    fi
  '';
}
