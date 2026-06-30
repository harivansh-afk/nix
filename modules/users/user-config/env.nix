# Session environment: the old home/xdg.nix + sessionVariables.
#
#   sessionVars   - sourced by the zsh shim into every shell.
#   environmentD  - systemd ~/.config/environment.d drop-in (linux PAM).
{
  pkgs,
  theme,
  binHome,
  configHome,
  dataHome,
  stateHome,
  cacheHome,
  ...
}:
{
  sessionVars = pkgs.writeText "session-vars.zsh" ''
    export XDG_BIN_HOME="${binHome}"
    export XDG_CONFIG_HOME="${configHome}"
    export XDG_DATA_HOME="${dataHome}"
    export XDG_STATE_HOME="${stateHome}"
    export XDG_CACHE_HOME="${cacheHome}"

    export LESSHISTFILE="-"
    export WGETRC="${configHome}/wgetrc"

    export CARGO_HOME="${dataHome}/cargo"
    export RUSTUP_HOME="${dataHome}/rustup"

    export GOPATH="${dataHome}/go"
    export GOMODCACHE="${cacheHome}/go/mod"

    export NPM_CONFIG_USERCONFIG="${configHome}/npm/npmrc"
    export NODE_REPL_HISTORY="${stateHome}/node_repl_history"
    export PNPM_HOME="${dataHome}/pnpm"
    export PNPM_NO_UPDATE_NOTIFIER="true"

    export PYTHONSTARTUP="${configHome}/python/pythonrc"
    export PYTHON_HISTORY="${stateHome}/python_history"
    export PYTHONPYCACHEPREFIX="${cacheHome}/python"
    export PYTHONUSERBASE="${dataHome}/python"

    export DOCKER_CONFIG="${configHome}/docker"

    export AWS_SHARED_CREDENTIALS_FILE="${configHome}/aws/credentials"
    export AWS_CONFIG_FILE="${configHome}/aws/config"

    export PSQL_HISTORY="${stateHome}/psql_history"
    export SQLITE_HISTORY="${stateHome}/sqlite_history"

    export FZF_DEFAULT_OPTS_FILE="${theme.paths.fzfCurrentFile}"

    export PATH="${binHome}:${dataHome}/cargo/bin:${dataHome}/go/bin:${dataHome}/npm/bin:${dataHome}/pnpm:$PATH"
  '';

  environmentD = pkgs.writeText "user-environment.conf" ''
    XDG_BIN_HOME=${binHome}
    XDG_CACHE_HOME=${cacheHome}
    XDG_CONFIG_HOME=${configHome}
    XDG_DATA_HOME=${dataHome}
    XDG_STATE_HOME=${stateHome}
  '';
}
