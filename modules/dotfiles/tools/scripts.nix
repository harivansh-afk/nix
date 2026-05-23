{
  pkgs,
  lib,
  hostConfig,
  paths,
  ...
}:
let
  customScripts = import ../../../scripts { inherit paths lib pkgs; };
in
{
  packages =
    builtins.attrValues customScripts.commonPackages
    ++ lib.optionals hostConfig.isDarwin (builtins.attrValues customScripts.darwinPackages);

  activationLines = ''
    ${customScripts.themeAssetsText}

    mkdir -p ${lib.escapeShellArg customScripts.theme.paths.stateDir} \
             ${lib.escapeShellArg customScripts.theme.paths.fzfDir} \
             ${lib.escapeShellArg customScripts.theme.paths.ghosttyDir} \
             ${lib.escapeShellArg customScripts.theme.paths.tmuxDir} \
             ${lib.escapeShellArg customScripts.theme.paths.lazygitDir} \
             ${lib.escapeShellArg customScripts.theme.paths.gitDir} \
             ${lib.escapeShellArg customScripts.theme.wallpapers.dir}

    if [[ -f ${lib.escapeShellArg customScripts.theme.paths.stateFile} ]]; then
      mode=$(tr -d '[:space:]' < ${lib.escapeShellArg customScripts.theme.paths.stateFile})
    else
      mode=${lib.escapeShellArg customScripts.theme.defaultMode}
    fi

    mode="$(theme_normalize_mode "$mode")"
    printf '%s\n' "$mode" > ${lib.escapeShellArg customScripts.theme.paths.stateFile}
    theme_load_mode_assets "$mode"

    ln -sfn "$THEME_FZF_TARGET"        ${lib.escapeShellArg customScripts.theme.paths.fzfCurrentFile}
    ln -sfn "$THEME_GHOSTTY_TARGET"    ${lib.escapeShellArg customScripts.theme.paths.ghosttyCurrentFile}
    ln -sfn "$THEME_TMUX_TARGET"       ${lib.escapeShellArg customScripts.theme.paths.tmuxCurrentFile}
    ln -sfn "$THEME_LAZYGIT_TARGET"    ${lib.escapeShellArg customScripts.theme.paths.lazygitCurrentFile}
    ln -sfn "$THEME_GIT_THEME_TARGET"  ${lib.escapeShellArg customScripts.theme.paths.gitThemeCurrentFile}
    ${lib.optionalString hostConfig.isDarwin ''
      lg_darwin="$HOME/Library/Application Support/lazygit"
      mkdir -p "$lg_darwin"
      ln -sfn "$THEME_DARWIN_LAZYGIT_TARGET" "$lg_darwin/config.yml"
    ''}

    if [[ ! -f ${lib.escapeShellArg customScripts.theme.wallpapers.dark} ]]; then
      cp ${lib.escapeShellArg (toString customScripts.theme.wallpapers.staticDark)} \
         ${lib.escapeShellArg customScripts.theme.wallpapers.dark}
    fi
    if [[ ! -f ${lib.escapeShellArg customScripts.theme.wallpapers.light} ]]; then
      cp ${lib.escapeShellArg (toString customScripts.theme.wallpapers.staticLight)} \
         ${lib.escapeShellArg customScripts.theme.wallpapers.light}
    fi

    ln -sfn "$THEME_WALLPAPER" ${lib.escapeShellArg customScripts.theme.wallpapers.current}
  '';
}
