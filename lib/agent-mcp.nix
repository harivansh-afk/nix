# MCP servers that every agent harness on spark gets: Claude Code renders
# them into ~/.claude.json, Hermes into its config.yaml. Timeouts are seconds;
# each harness converts to its own unit.
{ pkgs }:
let
  bin = name: "/run/current-system/sw/bin/${name}";
  reload = "${import ../pkgs/mcp-reload { inherit pkgs; }}/bin/mcp-reload";
in
{
  packages = [
    (import ../pkgs/webjit { inherit pkgs; })
    (import ../pkgs/codex-mcp { inherit pkgs; })
  ];
  servers = {
    webjit = {
      command = reload;
      args = [
        (bin "webjit")
        "mcp"
      ];
      timeout = 300;
    };
    beeper.url = "http://127.0.0.1:23373/v0/mcp";
    codex = {
      command = reload;
      args = [ (bin "codex-mcp") ];
      timeout = 14400;
    };
  };
}
