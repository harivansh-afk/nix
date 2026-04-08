{
  config,
  lib,
  pkgs,
  hostConfig,
  ...
}:
let
  customScripts = import ../scripts { inherit config lib pkgs; };
in
{
  home.packages =
    builtins.attrValues customScripts.commonPackages
    ++ lib.optionals hostConfig.isDarwin (builtins.attrValues customScripts.darwinPackages);

  home.activation.initializeThemeState = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${customScripts.themeAssetsText}

    mkdir -p "${customScripts.theme.paths.stateDir}" \
             "${customScripts.theme.paths.fzfDir}" \
             "${customScripts.theme.paths.ghosttyDir}" \
             "${customScripts.theme.paths.tmuxDir}" \
             "${customScripts.theme.paths.lazygitDir}" \
             "${customScripts.theme.wallpapers.dir}"

    if [[ -f "${customScripts.theme.paths.stateFile}" ]]; then
      mode=$(tr -d '[:space:]' < "${customScripts.theme.paths.stateFile}")
    else
      mode="${customScripts.theme.defaultMode}"
    fi

    mode="$(theme_normalize_mode "$mode")"
    printf '%s\n' "$mode" > "${customScripts.theme.paths.stateFile}"
    theme_load_mode_assets "$mode"

    ln -sfn "$THEME_FZF_TARGET" "${customScripts.theme.paths.fzfCurrentFile}"
    ln -sfn "$THEME_GHOSTTY_TARGET" "${customScripts.theme.paths.ghosttyCurrentFile}"
    ln -sfn "$THEME_TMUX_TARGET" "${customScripts.theme.paths.tmuxCurrentFile}"
    ln -sfn "$THEME_LAZYGIT_TARGET" "${customScripts.theme.paths.lazygitCurrentFile}"
    ${lib.optionalString hostConfig.isDarwin ''
    lg_darwin="${config.home.homeDirectory}/Library/Application Support/lazygit"
    mkdir -p "$lg_darwin"
    ln -sfn "$THEME_DARWIN_LAZYGIT_TARGET" "$lg_darwin/config.yml"
    ''}

    # seed wallpapers from static assets if no generated ones exist yet
    if [[ ! -f "${customScripts.theme.wallpapers.dark}" ]]; then
      cp "${customScripts.theme.wallpapers.staticDark}" "${customScripts.theme.wallpapers.dark}"
    fi
    if [[ ! -f "${customScripts.theme.wallpapers.light}" ]]; then
      cp "${customScripts.theme.wallpapers.staticLight}" "${customScripts.theme.wallpapers.light}"
    fi

    # ensure wallpaper symlink points to active mode
    ln -sfn "$THEME_WALLPAPER" "${customScripts.theme.wallpapers.current}"
  '';
}
