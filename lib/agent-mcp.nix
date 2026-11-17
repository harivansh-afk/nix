{ pkgs }:
{
  packages = [
    (import ../pkgs/codex-mcp { inherit pkgs; })
  ];
  servers = {
    beeper.url = "http://127.0.0.1:23373/v0/mcp";
    codex = {
      command = "/run/current-system/sw/bin/codex-mcp";
      timeout = 14400;
    };
  };
}
