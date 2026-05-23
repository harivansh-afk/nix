{
  config,
  pkgs,
  ...
}:
let
  jsonFormat = pkgs.formats.json { };
  hookCommand = name: "${config.homeDirectory}/.claude/hooks/${name}";
  claudeSettings = jsonFormat.generate "claude-settings.json" {
    "$schema" = "https://json.schemastore.org/claude-code-settings.json";
    env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
    model = "opus[1m]";
    permissions.defaultMode = "bypassPermissions";
    includeCoAuthoredBy = false;
    autoCompactEnabled = true;
    statusLine = {
      type = "command";
      command = "${config.homeDirectory}/.claude/statusline.sh";
    };
    voiceEnabled = true;
    hooks = {
      SessionStart = [
        {
          hooks = [
            {
              type = "command";
              command = hookCommand "session-start.sh";
            }
          ];
        }
        {
          hooks = [
            {
              type = "command";
              command = hookCommand "session-id.sh";
              timeout = 5;
            }
          ];
        }
      ];
      PreToolUse = [
        {
          matcher = "Bash";
          hooks = [
            {
              type = "command";
              command = hookCommand "enforce-modern-tools.sh";
            }
          ];
        }
      ];
    };
  };
in
{
  files.".claude/CLAUDE.md".source = ../../../dots/claude/CLAUDE.md;
  files.".claude/commands" = {
    source = ../../../dots/claude/commands;
    recursive = true;
  };
  files.".claude/settings.json".source = claudeSettings;
  files.".claude/statusline.sh" = {
    source = ../../../dots/claude/statusline.sh;
    executable = true;
  };
  files.".claude/hooks/session-start.sh" = {
    source = ../../../dots/claude/hooks/session-start.sh;
    executable = true;
  };
  files.".claude/hooks/session-id.sh" = {
    source = ../../../dots/claude/hooks/session-id.sh;
    executable = true;
  };
  files.".claude/hooks/enforce-modern-tools.sh" = {
    source = ../../../dots/claude/hooks/enforce-modern-tools.sh;
    executable = true;
  };
}
