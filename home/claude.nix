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
    env = {
      CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
    };
    permissions = {
      defaultMode = "bypassPermissions";
    };
    hooks = {
      PreToolUse = [
        {
          matcher = "Read";
          hooks = [
            {
              type = "command";
              command = "${config.home.homeDirectory}/.claude/sync-docs.sh";
            }
          ];
        }
      ];
    };
    statusLine = {
      type = "command";
      command = "${config.home.homeDirectory}/.claude/statusline.sh";
    };
    voiceEnabled = true;
  };
in
{
  home.file.".local/bin/claude".source = "${claudePackage}/bin/claude";

  # Claude Code stores shared config, commands, plugins, and skills in ~/.claude.
  # Global UI settings changed through /config still live in ~/.claude.json and are
  # intentionally left user-managed because Claude mutates that file directly.
  home.file.".claude/CLAUDE.md".source = ../config/claude/CLAUDE.md;
  home.file.".claude/commands" = {
    source = ../config/claude/commands;
    recursive = true;
  };
  home.file.".claude/settings.json".source = claudeSettings;
  home.file.".claude/settings.local.json".source = ../config/claude/settings.local.json;
  home.file.".claude/keybindings.json".source = ../config/claude/keybindings.json;
  home.file.".claude/statusline.sh" = {
    source = ../config/claude/statusline.sh;
    executable = true;
  };
  home.file.".claude/sync-docs.sh" = {
    source = ../config/claude/sync-docs.sh;
    executable = true;
  };
}
