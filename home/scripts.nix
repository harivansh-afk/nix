{
  config,
  lib,
  pkgs,
  ...
}: let
  customScripts = import ../scripts {inherit config lib pkgs;};
in {
  home.packages = builtins.attrValues customScripts.packages;

  home.activation.initializeThemeState = lib.hm.dag.entryAfter ["writeBoundary"] ''
    mkdir -p "${customScripts.theme.paths.stateDir}" "${customScripts.theme.paths.fzfDir}" "${customScripts.theme.paths.ghosttyDir}" "${customScripts.theme.paths.tmuxDir}"

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
        ;;
      *)
        printf '%s\n' "${customScripts.theme.defaultMode}" > "${customScripts.theme.paths.stateFile}"
        fzf_target="${customScripts.theme.paths.fzfDir}/cozybox-dark"
        ghostty_target="${customScripts.theme.paths.ghosttyDir}/cozybox-dark"
        tmux_target="${customScripts.tmuxConfigs.dark}"
        ;;
    esac

    ln -sfn "$fzf_target" "${customScripts.theme.paths.fzfCurrentFile}"
    ln -sfn "$ghostty_target" "${customScripts.theme.paths.ghosttyCurrentFile}"
    ln -sfn "$tmux_target" "${customScripts.theme.paths.tmuxCurrentFile}"
  '';
}
