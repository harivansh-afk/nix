{
  pkgs,
  homeDirectory,
  dotsRoot,
  isDarwin,
  theme,
  ...
}:
let
  jsonFormat = pkgs.formats.json { };
  yamlFormat = pkgs.formats.yaml { };
  hookCommand = hook: "${homeDirectory}/.claude/hooks/${hook}";

  mkReadXattr =
    xattrName:
    if isDarwin then
      ''/usr/bin/xattr -p "${xattrName}" "$target" 2>/dev/null''
    else
      ''${pkgs.attr}/bin/getfattr --only-values -n "${xattrName}" "$target" 2>/dev/null'';

  mkWriteXattr =
    xattrName:
    if isDarwin then
      ''/usr/bin/xattr -w "${xattrName}" "$source" "$target"''
    else
      ''${pkgs.attr}/bin/setfattr -n "${xattrName}" -v "$source" "$target"'';

  codexXattr = "user.hari.codex-seed-source";
  ompXattr = "user.hari.omp-seed-source";
in
{
  claudeSettings = jsonFormat.generate "claude-settings.json" {
    "$schema" = "https://json.schemastore.org/claude-code-settings.json";
    env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
    model = "claude-fable-5";
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

  codexConfigSource = "${dotsRoot}/codex/config.toml";

  readXattr = mkReadXattr codexXattr;
  writeXattr = mkWriteXattr codexXattr;

  ompThemes = {
    dark = jsonFormat.generate "omp-cozybox-dark.json" (theme.ompTheme "dark");
    light = jsonFormat.generate "omp-cozybox-light.json" (theme.ompTheme "light");
  };

  ompConfigSource = yamlFormat.generate "omp-config.yml" {
    theme = {
      dark = "cozybox-dark";
      light = "cozybox-light";
    };
    startup.quiet = true;
    symbolPreset = "ascii";
    statusLine = {
      preset = "custom";
      leftSegments = [
        "model"
        "path"
        "git"
      ];
      rightSegments = [ "context_pct" ];
      segmentOptions = {
        model.showThinkingLevel = true;
        path = {
          abbreviate = true;
          maxLength = 40;
          stripWorkPrefix = true;
        };
        git = {
          showBranch = true;
          showStaged = true;
          showUnstaged = true;
          showUntracked = false;
        };
      };
      separator = "pipe";
      transparent = true;
    };
  };

  ompReadXattr = mkReadXattr ompXattr;
  ompWriteXattr = mkWriteXattr ompXattr;
}
