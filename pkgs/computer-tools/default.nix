{ pkgs }:
let
  cuaDriver = pkgs.callPackage ../cua-driver { };
  cuaMcp = pkgs.writeShellApplication {
    name = "spark-cua-mcp";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
      exec ${cuaDriver}/bin/cua-driver mcp --socket "$XDG_RUNTIME_DIR/cua-driver/control.sock" "$@"
    '';
  };
in
{
  inherit cuaMcp;
  agentBrowser = pkgs.callPackage ../agent-browser { };
  servers = {
    computer = {
      command = "${cuaMcp}/bin/spark-cua-mcp";
      args = [ ];
    };
  };
}
