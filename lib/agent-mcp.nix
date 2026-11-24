{ pkgs }:
let
  kernelConfig = (pkgs.formats.json { }).generate "ts-kernel-servers.json" {
    mcpServers = {
      beeper = {
        url = "http://127.0.0.1:23373/v0/mcp";
        scope = "read write";
      };
    };
  };
  tsKernel = pkgs.writeShellScriptBin "ts-kernel" ''
    exec ${pkgs.ts-kernel}/bin/ts-kernel --config ${kernelConfig} "$@"
  '';
in
{
  packages = [
    (import ../pkgs/codex-mcp { inherit pkgs; })
    tsKernel
  ];
  servers = {
    ts = {
      command = "/run/current-system/sw/bin/ts-kernel";
      timeout = 600;
    };
    codex = {
      command = "/run/current-system/sw/bin/codex-mcp";
      timeout = 14400;
    };
  };
}
