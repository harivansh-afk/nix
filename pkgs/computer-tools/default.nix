{ pkgs }:
let
  cuaDriver = pkgs.callPackage ../cua-driver { };
  browserDomUse = pkgs.callPackage ../browser-dom-use { };
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
  inherit browserDomUse;
  servers = {
    computer = {
      command = "${cuaMcp}/bin/spark-cua-mcp";
      args = [ ];
    };
    # bdu: browser for agents, one model call per task. Attaches to the running Chrome on
    # port 19222; ANTHROPIC_* come from the harness environment.
    bdu = {
      command = "${browserDomUse}/bin/bdu";
      args = [ "mcp" ];
    };
  };
}
