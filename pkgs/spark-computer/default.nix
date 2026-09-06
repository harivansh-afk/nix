{ pkgs }:
let
  python = pkgs.python3.withPackages (ps: [
    ps.mcp
    ps.playwright
    ps.pillow
  ]);
  cuaDriver = pkgs.callPackage ../cua-driver { };
in
(pkgs.writeShellApplication {
  name = "spark-computer";
  runtimeInputs = [ python ];
  text = ''
    export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    export SPARK_BROWSER_CDP="''${SPARK_BROWSER_CDP:-http://127.0.0.1:19222}"
    export CUA_DRIVER_COMMAND="${cuaDriver}/bin/cua-driver"
    export CUA_DRIVER_SOCKET="''${CUA_DRIVER_SOCKET:-$XDG_RUNTIME_DIR/cua-driver/control.sock}"
    export CUA_DRIVER_RS_TELEMETRY_ENABLED=0
    export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
    exec ${python}/bin/python ${./server.py} "$@"
  '';
}).overrideAttrs
  (old: {
    passthru = (old.passthru or { }) // {
      inherit python;
    };
  })
