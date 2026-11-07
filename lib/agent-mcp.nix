# MCP servers that every agent harness on spark gets: Claude Code renders
# them into ~/.claude.json, Hermes into its config.yaml. Timeouts are seconds;
# each harness converts to its own unit.
{ pkgs }:
let
  webjit = import ../pkgs/webjit { inherit pkgs; };
  codexMcp = import ../pkgs/codex-mcp { inherit pkgs; };
in
{
  webjit = {
    command = "${webjit}/bin/webjit";
    args = [ "mcp" ];
    timeout = 300;
  };
  beeper.url = "http://127.0.0.1:23373/v0/mcp";
  codex = {
    command = "${codexMcp}/bin/codex-mcp";
    timeout = 14400;
  };
}
