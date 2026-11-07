{ pkgs }:
pkgs.writeShellScriptBin "mcp-reload" ''
  exec ${pkgs.python3}/bin/python3 ${./relay.py} "$@"
''
