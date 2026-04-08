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
      printf '%s\n' "$mode" > "${customScripts.theme.paths.stateFile}"
    fi

    case "$mode" in
      light)
        fzf_target="${customScripts.theme.paths.fzfDir}/cozybox-light"
        ghostty_target="${customScripts.theme.paths.ghosttyDir}/cozybox-light"
        tmux_target="${customScripts.tmuxConfigs.light}"
        lazygit_target="${customScripts.theme.paths.lazygitDir}/config-light.yml"
        ;;
      *)
        printf '%s\n' "${customScripts.theme.defaultMode}" > "${customScripts.theme.paths.stateFile}"
        fzf_target="${customScripts.theme.paths.fzfDir}/cozybox-dark"
        ghostty_target="${customScripts.theme.paths.ghosttyDir}/cozybox-dark"
        tmux_target="${customScripts.tmuxConfigs.dark}"
        lazygit_target="${customScripts.theme.paths.lazygitDir}/config-dark.yml"
        ;;
    esac

    ln -sfn "$fzf_target" "${customScripts.theme.paths.fzfCurrentFile}"
    ln -sfn "$ghostty_target" "${customScripts.theme.paths.ghosttyCurrentFile}"
    ln -sfn "$tmux_target" "${customScripts.theme.paths.tmuxCurrentFile}"
    ln -sfn "$lazygit_target" "${customScripts.theme.paths.lazygitCurrentFile}"
    ${lib.optionalString hostConfig.isDarwin ''
    lg_darwin="${config.home.homeDirectory}/Library/Application Support/lazygit"
    mkdir -p "$lg_darwin"
    case "$mode" in
      light) ln -sfn "$lg_darwin/config-light.yml" "$lg_darwin/config.yml" ;;
      *)     ln -sfn "$lg_darwin/config-dark.yml" "$lg_darwin/config.yml" ;;
    esac
    ''}

    # seed wallpapers from static assets if no generated ones exist yet
    if [[ ! -f "${customScripts.theme.wallpapers.dark}" ]]; then
      cp "${customScripts.theme.wallpapers.staticDark}" "${customScripts.theme.wallpapers.dark}"
    fi
    if [[ ! -f "${customScripts.theme.wallpapers.light}" ]]; then
      cp "${customScripts.theme.wallpapers.staticLight}" "${customScripts.theme.wallpapers.light}"
    fi

    # ensure wallpaper symlink points to active mode
    case "$mode" in
      light) wp_target="${customScripts.theme.wallpapers.light}" ;;
      *)     wp_target="${customScripts.theme.wallpapers.dark}" ;;
    esac
    ln -sfn "$wp_target" "${customScripts.theme.wallpapers.current}"
  '';
}
