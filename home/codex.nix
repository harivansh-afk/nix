{ inputs, pkgs, ... }:
let
  codexPackage = inputs.codex-cli.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  home.packages = [ codexPackage ];
  home.file.".codex/AGENTS.md".source = ../dots/codex/AGENTS.md;
  home.file.".codex/config.toml".source = ../dots/codex/config.toml;
}
