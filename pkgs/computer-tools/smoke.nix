{ pkgs }:
let
  tools = import ./. { inherit pkgs; };
  python = pkgs.python3.withPackages (ps: [ ps.mcp ]);
  cuaDriver = pkgs.callPackage ../cua-driver { };
in
pkgs.writeShellApplication {
  name = "computer-smoke";
  runtimeInputs = [
    python
    pkgs.dbus
    pkgs.sway
  ];
  runtimeEnv = {
    AGENT_BROWSER = "${tools.agentBrowser}/bin/agent-browser";
    CHROMIUM = "${pkgs.chromium}/bin/chromium";
    CUA_DRIVER = "${cuaDriver}/bin/cua-driver";
    CUA_MCP = "${tools.cuaMcp}/bin/spark-cua-mcp";
    ZENITY = "${pkgs.zenity}/bin/zenity";
  };
  text = ''
    python ${../../scripts/upstream-browser-smoke.py}
    python ${../../scripts/upstream-native-smoke.py}
  '';
}
