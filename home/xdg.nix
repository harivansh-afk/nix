{
  config,
  lib,
  hostConfig,
  ...
}:
let
  f = hostConfig.features;
in
{
  home.sessionVariables = lib.mkMerge [
    {
      LESSHISTFILE = "-";
      WGETRC = "${config.xdg.configHome}/wgetrc";
    }
    (lib.mkIf (f.rust or false) {
      CARGO_HOME = "${config.xdg.dataHome}/cargo";
      RUSTUP_HOME = "${config.xdg.dataHome}/rustup";
    })
    (lib.mkIf (f.go or false) {
      GOPATH = "${config.xdg.dataHome}/go";
      GOMODCACHE = "${config.xdg.cacheHome}/go/mod";
    })
    (lib.mkIf (f.node or false) {
      NPM_CONFIG_USERCONFIG = "${config.xdg.configHome}/npm/npmrc";
      NODE_REPL_HISTORY = "${config.xdg.stateHome}/node_repl_history";
      PNPM_HOME = "${config.xdg.dataHome}/pnpm";
      PNPM_NO_UPDATE_NOTIFIER = "true";
    })
    (lib.mkIf (f.python or false) {
      PYTHONSTARTUP = "${config.xdg.configHome}/python/pythonrc";
      PYTHON_HISTORY = "${config.xdg.stateHome}/python_history";
      PYTHONPYCACHEPREFIX = "${config.xdg.cacheHome}/python";
      PYTHONUSERBASE = "${config.xdg.dataHome}/python";
    })
    (lib.mkIf (f.docker or false) {
      DOCKER_CONFIG = "${config.xdg.configHome}/docker";
    })
    (lib.mkIf (f.aws or false) {
      AWS_SHARED_CREDENTIALS_FILE = "${config.xdg.configHome}/aws/credentials";
      AWS_CONFIG_FILE = "${config.xdg.configHome}/aws/config";
    })
    {
      PSQL_HISTORY = "${config.xdg.stateHome}/psql_history";
      SQLITE_HISTORY = "${config.xdg.stateHome}/sqlite_history";
    }
  ];

  home.sessionPath = lib.mkMerge [
    [ "${config.home.homeDirectory}/.local/bin" ]
    (lib.mkIf (f.rust or false) [ "${config.xdg.dataHome}/cargo/bin" ])
    (lib.mkIf (f.go or false) [ "${config.xdg.dataHome}/go/bin" ])
    (lib.mkIf (f.node or false) [
      "${config.xdg.dataHome}/npm/bin"
      "${config.xdg.dataHome}/pnpm"
    ])
  ];

  xdg.configFile."npm/npmrc" = lib.mkIf (f.node or false) {
    text = ''
      prefix=''${XDG_DATA_HOME}/npm
      cache=''${XDG_CACHE_HOME}/npm
      init-module=''${XDG_CONFIG_HOME}/npm/config/npm-init.js
    '';
  };

  xdg.configFile."python/pythonrc" = lib.mkIf (f.python or false) {
    text = ''
      import atexit
      import os
      import readline

      history = os.path.join(os.environ.get('XDG_STATE_HOME', os.path.expanduser('~/.local/state')), 'python_history')

      try:
          readline.read_history_file(history)
      except OSError:
          pass

      def write_history():
          try:
              readline.write_history_file(history)
          except OSError:
              pass

      atexit.register(write_history)
    '';
  };

  xdg.configFile."wgetrc".text = ''
    hsts_file = ${config.xdg.stateHome}/wget-hsts
  '';
}
