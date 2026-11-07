# MCP servers that every agent harness on spark gets: Claude Code renders
# them into ~/.claude.json, Hermes into its config.yaml. Timeouts are seconds;
# each harness converts to its own unit.
{ pkgs }:
let
  bin = name: "/run/current-system/sw/bin/${name}";
in
{
  packages = [
    (import ../pkgs/webjit { inherit pkgs; })
    (import ../pkgs/codex-mcp { inherit pkgs; })
  ];
  servers = {
    webjit = {
      command = bin "webjit";
      args = [ "mcp" ];
      timeout = 300;
    };
    beeper.url = "http://127.0.0.1:23373/v0/mcp";
    codex = {
      command = bin "codex-mcp";
      timeout = 14400;
    };
  };
}
