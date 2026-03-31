{
  inputs,
  pkgs,
  ...
}:
let
  claudePackage = inputs.claudeCode.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  home.file.".local/bin/claude".source = "${claudePackage}/bin/claude";

  xdg.configFile."claude/CLAUDE.md".source = ../config/claude/CLAUDE.md;
  xdg.configFile."claude/commands" = {
    source = ../config/claude/commands;
    recursive = true;
  };
  xdg.configFile."claude/settings.json".source = ../config/claude/settings.json;
  xdg.configFile."claude/settings.local.json".source = ../config/claude/settings.local.json;
  xdg.configFile."claude/statusline.sh" = {
    source = ../config/claude/statusline.sh;
    executable = true;
  };
}
