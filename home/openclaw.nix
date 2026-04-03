{
  config,
  lib,
  pkgs,
  hostConfig,
  ...
}:
let
  openClawStateDir = "${config.home.homeDirectory}/.openclaw";
  openClawWorkspaceDir = "${openClawStateDir}/workspace";
  openClawVersion = "2026.4.2";
  npmDir = "${config.xdg.dataHome}/npm";
in
lib.mkIf hostConfig.isLinux {
  home.activation.installOpenClaw = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    export PATH="${
      lib.makeBinPath [
        pkgs.nodejs_22
        pkgs.coreutils
      ]
    }:$PATH"
    export NPM_CONFIG_USERCONFIG="${config.xdg.configHome}/npm/npmrc"
    export XDG_DATA_HOME="${config.xdg.dataHome}"
    export XDG_CACHE_HOME="${config.xdg.cacheHome}"

    INSTALLED=$(npm ls -g openclaw --depth=0 --json 2>/dev/null | ${pkgs.jq}/bin/jq -r '.dependencies.openclaw.version // empty')
    if [ "$INSTALLED" != "${openClawVersion}" ]; then
      npm install -g "openclaw@${openClawVersion}" 2>/dev/null || true
    fi
  '';

  home.activation.syncOpenClawState = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    install -d -m 700 "${openClawStateDir}" "${openClawWorkspaceDir}"
    install -m 600 ${../config/openclaw/openclaw.json} "${openClawStateDir}/openclaw.json"
    install -m 644 ${../config/openclaw/SOUL.md} "${openClawWorkspaceDir}/SOUL.md"
  '';
}
