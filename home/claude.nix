{
  inputs,
  pkgs,
  ...
}:
let
  claudePackage = inputs.claudeCode.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  # Keep the managed Claude binary on the same path the live machine was using
  # so the Nix package cleanly replaces the prior manual install.
  home.file.".local/bin/claude".source = "${claudePackage}/bin/claude";
  home.file.".claude/CLAUDE.md".source = ../config/claude/CLAUDE.md;
  home.file.".claude/commands" = {
    source = ../config/claude/commands;
    recursive = true;
  };
  home.file.".claude/settings.json".source = ../config/claude/settings.json;
  home.file.".claude/settings.local.json".source = ../config/claude/settings.local.json;
  home.file.".claude/statusline.sh" = {
    source = ../config/claude/statusline.sh;
    executable = true;
  };
}
