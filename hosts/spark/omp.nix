{ pkgs, ... }:
let
  ixMcp = pkgs.writeShellScriptBin "ix-mcp" ''
    exec nix run --accept-flake-config /home/rathi/Documents/Git/indexable/index#mcp -- "$@"
  '';
in
{
  environment.systemPackages = [ ixMcp ];
}
