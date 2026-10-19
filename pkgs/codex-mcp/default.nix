{ pkgs }:
let
  python = pkgs.python3.withPackages (ps: [ ps.mcp ]);
in
pkgs.writeShellScriptBin "codex-mcp" ''
  exec ${python}/bin/python3 ${./server.py} "$@"
''
