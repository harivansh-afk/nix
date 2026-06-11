{
  config,
  pkgs,
  ...
}:
let
  jsonFormat = pkgs.formats.json { };
  hookCommand = name: "${config.home.homeDirectory}/.claude/hooks/${name}";
  claudeSettings = jsonFormat.generate "claude-settings.json" {
    "$schema" = "https://json.schemastore.org/claude-code-settings.json";
    env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
    model = "claude-fable-5";
    # Stay on the classic renderer; the v2.1.110+ fullscreen TUI breaks
    # native scrollback / Cmd+f / tmux copy-mode. Override with /tui fullscreen
    # if you want to opt in for a session.
    tui = "default";
    permissions.defaultMode = "bypassPermissions";
    includeCoAuthoredBy = false;
    autoCompactEnabled = true;
    showThinkingSummaries = true;
    statusLine = {
      type = "command";
      command = "${config.home.homeDirectory}/.claude/statusline.sh";
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
    };
  };
in
{
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
  home.file.".claude/hooks/session-start.sh" = {
    source = ../dots/claude/hooks/session-start.sh;
    executable = true;
  };
  home.file.".claude/hooks/session-id.sh" = {
    source = ../dots/claude/hooks/session-id.sh;
    executable = true;
  };
}
