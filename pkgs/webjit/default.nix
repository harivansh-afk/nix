{ pkgs }:
pkgs.writeShellApplication {
  name = "webjit";
  text = ''
    export WEBJIT_CDP="''${WEBJIT_CDP:-http://127.0.0.1:19222}"
    exec ${pkgs.webjit}/bin/webjit "$@"
  '';
}
