{
  config,
  inputs,
  pkgs,
  hostConfig,
  lib,
  ...
}:
let
  openClawVersion = "2026.4.2";
  npmDir = "${config.xdg.dataHome}/npm";
in
lib.mkIf hostConfig.isLinux {
  home.packages = [
    inputs.openClaw.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  home.activation.installOpenClaw = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    export PATH="${lib.makeBinPath [ pkgs.nodejs_22 pkgs.coreutils ]}:$PATH"
    export NPM_CONFIG_USERCONFIG="${config.xdg.configHome}/npm/npmrc"
    export XDG_DATA_HOME="${config.xdg.dataHome}"
    export XDG_CACHE_HOME="${config.xdg.cacheHome}"

    OPENCLAW_DIR="${npmDir}/lib/node_modules/openclaw"
    INSTALLED=$(npm ls -g openclaw --depth=0 --json 2>/dev/null | ${pkgs.jq}/bin/jq -r '.dependencies.openclaw.version // empty')
    HEALTHY=true
    [ "$INSTALLED" != "${openClawVersion}" ] && HEALTHY=false
    [ ! -d "$OPENCLAW_DIR/node_modules/grammy" ] && HEALTHY=false
    if [ "$HEALTHY" = false ]; then
      npm install -g "openclaw@${openClawVersion}" --force 2>/dev/null || true
    fi
  '';

  home.file.".openclaw/workspace/SOUL.md".source = ../config/openclaw/SOUL.md;
}
