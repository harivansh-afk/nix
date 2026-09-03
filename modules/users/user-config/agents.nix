{
  lib,
  pkgs,
  homeDirectory,
  isDarwin,
  theme,
  skillSources,
  ...
}:
let
  agentInstructions = import ../../../lib/agent-instructions.nix { inherit pkgs; };

  # Opt-in allowlist: each upstream skill costs context on every turn (its
  # description is always loaded), so add one here only after reading it.
  pocockPick = [
    "productivity/writing-for-agents"
    "engineering/research"
  ];
  pocockSkills = lib.optionals (skillSources ? mattpocock) (
    map (rel: {
      name = baseNameOf rel;
      path = "${skillSources.mattpocock}/skills/${rel}";
    }) pocockPick
  );

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

  # MCP servers for omp (~/.omp/agent/mcp.json). `index` is ix-mcp, the
  # indexable Python-kernel MCP server; the `ix-mcp` on PATH is the spark-only
  # wrapper around the live checkout (hosts/spark/omp.nix), so the entry is
  # emitted only off-darwin.
  ompMcpServers = lib.optionalAttrs (!isDarwin) {
    index = {
      command = "ix-mcp";
      args = [ "serve" ];
    };
  };
in
{
  claudeMd = agentInstructions.claude;
  codexAgentsMd = agentInstructions.codex;
  agentSkills = pkgs.linkFarm "agent-skills" pocockSkills;

  claudeSettings = jsonFormat.generate "claude-settings.json" {
    "$schema" = "https://json.schemastore.org/claude-code-settings.json";
    env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
    model = "claude-fable-5-1";
    tui = "fullscreen";
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

  ompMcpSource = jsonFormat.generate "omp-mcp.json" { mcpServers = ompMcpServers; };

  # Session overlay for local inference: `omp --config ~/.omp/agent/local.yml`.
  # Role syntax: provider/model[:thinking]; `default` drives the main session
  # model, `task` is what subagents resolve at spawn time.
  ompLocalSource = yamlFormat.generate "omp-local-mode.yml" {
    modelRoles = {
      default = "spark-local/qwen3.8-27b:medium";
      task = "spark-local/huihui-qwen3.8-27b-abliterated:medium";
    };
  };

  ompModelsSource = yamlFormat.generate "omp-models.yml" {
    providers.spark-local = {
      baseUrl = "http://127.0.0.1:18080/v1";
      api = "openai-completions";
      auth = "none";
      compat = {
        supportsStore = false;
        supportsDeveloperRole = false;
        supportsReasoningEffort = false;
        supportsStrictMode = false;
        maxTokensField = "max_tokens";
      };
      models = [
        {
          id = "qwen3.8-27b";
          name = "Qwen 3.8 27B UD-Q4_K_XL";
          reasoning = true;
          input = [ "text" ];
          contextWindow = 65536;
          maxTokens = 32768;
        }
        {
          id = "huihui-qwen3.8-27b-abliterated";
          name = "Huihui Qwen 3.8 27B Abliterated Q4_K";
          reasoning = true;
          input = [ "text" ];
          contextWindow = 65536;
          maxTokens = 32768;
        }
      ];
    };
  };

  ompConfigSource = yamlFormat.generate "omp-config.yml" {
    theme = {
      dark = "cozybox-dark";
      light = "cozybox-light";
    };
    # The activation script reseeds config.yml whenever this generated file
    # changes; without a pinned setupVersion each reseed resets it to 0 and the
    # onboarding wizard re-fires on next launch. Pin it to upstream's
    # CURRENT_SETUP_VERSION (src/modes/setup-version.ts): the cold-launch gate
    # in main.ts eagerly imports the whole setup-wizard barrel whenever the
    # stored version is lower, before startup.setupWizard is even consulted,
    # so a stale pin taxes every launch just to decide to skip the wizard.
    setupVersion = 2;
    startup = {
      quiet = true;
      setupWizard = false;
    };
    symbolPreset = "unicode";
    display.shimmer = "disabled";
    disabledProviders = [ "llama.cpp" ];
    todo.enabled = false;
    modelRoles = {
      default = "anthropic/claude-fable-5-1:high";
      task = "openai-codex/gpt-5.6-sol:low";
    };
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
