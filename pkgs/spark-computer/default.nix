{ pkgs }:
let
  python = pkgs.python3.withPackages (ps: [
    ps.mcp
    ps.playwright
  ]);
  cuaDriver = pkgs.callPackage ../cua-driver { };
in
pkgs.writeShellApplication {
  name = "spark-computer";
  runtimeInputs = [ python ];
  runtimeEnv = {
    CUA_DRIVER_COMMAND = "${cuaDriver}/bin/cua-driver";
    CUA_DRIVER_RS_TELEMETRY_ENABLED = "0";
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
  };
  text = ''
    export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    exec ${python}/bin/python ${./server.py} "$@"
  '';
}
