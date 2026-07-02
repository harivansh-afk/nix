# AI agent configs: claude settings (rendered) and the codex seed metadata.
#
# claude settings interpolate the home directory into hook paths. The codex
# config.toml cannot be a read-only store symlink (codex rewrites it at
# runtime), so it is seeded as a writable copy and reseeded only when the
# managed source changes, tracked via an extended attribute.
{
  pkgs,
  homeDirectory,
  dotsRoot,
  isDarwin,
  ...
}:
let
  jsonFormat = pkgs.formats.json { };
  hookCommand = hook: "${homeDirectory}/.claude/hooks/${hook}";
  xattrName = "user.hari.codex-seed-source";
in
{
  claudeSettings = jsonFormat.generate "claude-settings.json" {
    "$schema" = "https://json.schemastore.org/claude-code-settings.json";
    env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
    model = "claude-opus-4-8";
    # Stay on the classic renderer; the v2.1.110+ fullscreen TUI breaks
    # native scrollback / Cmd+f / tmux copy-mode. Override with /tui
    # fullscreen if you want to opt in for a session.
    tui = "default";
    permissions.defaultMode = "bypassPermissions";
    includeCoAuthoredBy = false;
    autoCompactEnabled = true;
    showThinkingSummaries = true;
    statusLine = {
      type = "command";
      command = "${homeDirectory}/.claude/statusline.sh";
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
        {
          hooks = [
            {
              type = "command";
              command = hookCommand "agent-session-state.sh";
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
        {
          matcher = "Edit|Write|NotebookEdit";
          hooks = [
            {
              type = "command";
              command = hookCommand "enforce-worktrees.sh";
            }
          ];
        }
      ];
      # No matcher: fires on every tool call so the session state file tracks
      # cwd/worktree as the agent moves (worktree creation, cd, edits).
      PostToolUse = [
        {
          hooks = [
            {
              type = "command";
              command = hookCommand "agent-session-state.sh";
              timeout = 5;
            }
          ];
        }
      ];
      Stop = [
        {
          hooks = [
            {
              type = "command";
              command = hookCommand "agent-session-state.sh";
              timeout = 5;
            }
          ];
        }
      ];
      SessionEnd = [
        {
          hooks = [
            {
              type = "command";
              command = hookCommand "agent-session-state.sh";
              timeout = 5;
            }
          ];
        }
      ];
    };
  };

  codexConfigSource = "${dotsRoot}/codex/config.toml";

  readXattr =
    if isDarwin then
      ''/usr/bin/xattr -p "${xattrName}" "$target" 2>/dev/null''
    else
      ''${pkgs.attr}/bin/getfattr --only-values -n "${xattrName}" "$target" 2>/dev/null'';

  writeXattr =
    if isDarwin then
      ''/usr/bin/xattr -w "${xattrName}" "$source" "$target"''
    else
      ''${pkgs.attr}/bin/setfattr -n "${xattrName}" -v "$source" "$target"'';
}
