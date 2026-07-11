{
  lib,
  pkgs,
  homeDirectory,
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

  # Named model-role bundles for the /mode command
  # (dots/omp/extensions/modes.ts). Each bundle REPLACES modelRoles wholesale
  # when applied. Role syntax: provider/model[:thinking][,fallback...].
  # `default` drives the main session model; `task` is what subagents resolve
  # at spawn time (the task agent's model is `pi/task`).
  ompModes = {
    default = {
      description = "fable-5 high main, gpt-5.6-sol low subagents";
      roles = {
        default = "anthropic/claude-fable-5:high";
        task = "openai-codex/gpt-5.6-sol:low";
      };
    };
  };

  # MCP servers for omp (~/.omp/agent/mcp.json). `index` is ix-mcp, the
  # indexable Python-kernel MCP server; the `ix-mcp` on PATH is the spark-only
  # wrapper around the live checkout (hosts/spark/pi.nix), so the entry is
  # emitted only off-darwin.
  ompMcpServers = lib.optionalAttrs (!isDarwin) {
    index = {
      command = "ix-mcp";
      args = [ "serve" ];
    };
  };
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

  codexConfigSource = pkgs.writeText "codex-config.toml" (
    builtins.readFile ../../../dots/codex/config.toml
  );

  readXattr = mkReadXattr codexXattr;
  writeXattr = mkWriteXattr codexXattr;

  ompThemes = {
    dark = jsonFormat.generate "omp-cozybox-dark.json" (theme.ompTheme "dark");
    light = jsonFormat.generate "omp-cozybox-light.json" (theme.ompTheme "light");
  };

  ompModesSource = jsonFormat.generate "omp-modes.json" ompModes;

  ompMcpSource = jsonFormat.generate "omp-mcp.json" { mcpServers = ompMcpServers; };

  ompConfigSource = yamlFormat.generate "omp-config.yml" {
    theme = {
      dark = "cozybox-dark";
      light = "cozybox-light";
    };
    # The activation script reseeds config.yml whenever this generated file
    # changes; without a pinned setupVersion each reseed resets it to 0 and the
    # onboarding wizard re-fires on next launch. Pin it and disable the wizard
    # outright so omp updates (which bump CURRENT_SETUP_VERSION) stay quiet too.
    setupVersion = 1;
    startup = {
      quiet = true;
      setupWizard = false;
    };
    symbolPreset = "unicode";
    display.shimmer = "disabled";
    todo.enabled = false;
    # Seed matches the `default` mode so a config reseed lands on it.
    modelRoles = ompModes.default.roles;
    statusLine = {
      preset = "custom";
      sessionAccent = false;
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
