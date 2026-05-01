{
  config,
  inputs,
  pkgs,
  ...
}:
let
  claudePackage = inputs.claudeCode.packages.${pkgs.stdenv.hostPlatform.system}.default;
  jsonFormat = pkgs.formats.json { };
  claudeSettings = jsonFormat.generate "claude-settings.json" {
    "$schema" = "https://json.schemastore.org/claude-code-settings.json";
    env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
    model = "opus[1m]";
    permissions.defaultMode = "bypassPermissions";
    includeCoAuthoredBy = false;
    statusLine = {
      type = "command";
      command = "${config.home.homeDirectory}/.claude/statusline.sh";
    };
    voiceEnabled = true;
  };
in
{
  home.file.".local/bin/claude".source = "${claudePackage}/bin/claude";
  home.file.".claude/CLAUDE.md".source = ../dots/claude/CLAUDE.md;
  home.file.".claude/commands" = {
    source = ../dots/claude/commands;
    recursive = true;
  };
  home.file.".claude/settings.json".source = claudeSettings;
  home.file.".claude/statusline.sh" = {
    source = ../dots/claude/statusline.sh;
    executable = true;
  };
}
