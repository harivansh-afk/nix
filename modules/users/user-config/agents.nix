{
  lib,
  homeDirectory,
  pkgs,
  hostname,
  isDarwin,
  skillSources,
  codexPlugin,
  ...
}:
let
  agentInstructions = import ../../../lib/agent-instructions.nix { inherit pkgs; };
  computer = import ../../../pkgs/computer-tools { inherit pkgs; };

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

  delegateToCodex = codexPlugin != null;

in
{
  claudeMd = agentInstructions.claude;

  piModels =
    if hostname == "spark" then
      jsonFormat.generate "pi-models.json" {
        providers.spark-local = {
          baseUrl = "http://127.0.0.1:18080/v1";
          api = "openai-completions";
          apiKey = "none";
          compat = {
            supportsStore = false;
            supportsDeveloperRole = false;
            supportsReasoningEffort = false;
            maxTokensField = "max_tokens";
          };
          models = [
            {
              id = "qwen3.8-flash-next";
              name = "Qwen 3.8 Flash Next (spark vLLM)";
              reasoning = true;
              input = [ "text" ];
              contextWindow = 65536;
              maxTokens = 32768;
            }
          ];
        };
      }
    else
      null;
  codexAgentsMd = agentInstructions.codex;
  agentSkills = pkgs.linkFarm "agent-skills" (
    pocockSkills
    ++ lib.optionals (hostname == "spark") [
      {
        name = "cua-driver";
        path = (pkgs.callPackage ../../../pkgs/cua-driver { }).skills;
      }
      {
        name = "spark-computer";
        path = ../../../dots/agents/skills/spark-computer;
      }
    ]
    ++ [
      {
        name = "paper-deck";
        path = ../../../dots/agents/skills/paper-deck;
      }
    ]
  );
  claudeMcpSource =
    if hostname == "spark" then
      jsonFormat.generate "claude-mcp.json" (
        (lib.mapAttrs (
          _: server:
          server
          // {
            type = "stdio";
            timeout = 60000;
          }
        ) computer.servers)
        // {
          beeper = {
            type = "http";
            url = "http://127.0.0.1:23373/v0/mcp";
          };
        }
      )
    else
      null;

  claudeSettings = jsonFormat.generate "claude-settings.json" (
    {
      "$schema" = "https://json.schemastore.org/claude-code-settings.json";
      env = {
        CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
      }
      // lib.optionalAttrs delegateToCodex {
        CODEX_COMPANION = "${codexPlugin}/plugins/codex/scripts/codex-companion.mjs";
        BASH_MAX_TIMEOUT_MS = "14400000";
      };
      model = "claude-fable-5-1";
      tui = "fullscreen";
      permissions = {
        defaultMode = "bypassPermissions";
      }
      // lib.optionalAttrs delegateToCodex {
        deny = [ "Agent" ];
      };
      includeCoAuthoredBy = false;
      autoCompactEnabled = true;
      autoMemoryEnabled = false;
      showThinkingSummaries = true;
      statusLine = {
        type = "command";
        command = "${homeDirectory}/.claude/statusline.sh";
      };
      voiceEnabled = true;
    }
    // lib.optionalAttrs delegateToCodex {
      extraKnownMarketplaces.openai-codex.source = {
        source = "directory";
        path = "${codexPlugin}";
      };
      enabledPlugins."codex@openai-codex" = true;
    }
  );

  codexConfigSource = pkgs.writeText "codex-config.toml" (
    lib.optionalString (hostname == "spark") ''
      model_provider = "codex-lb"
    ''
    + builtins.readFile ../../../dots/codex/config.toml
    + lib.optionalString (hostname == "spark") ''

      [model_providers.codex-lb]
      name = "openai"
      base_url = "http://127.0.0.1:18475/backend-api/codex"
      wire_api = "responses"
      supports_websockets = true
      supports_standalone_web_search = true
      requires_openai_auth = true

      [sandbox_workspace_write]
      network_access = true

      [mcp_servers.computer]
      command = "${computer.servers.computer.command}"
      startup_timeout_sec = 20
      tool_timeout_sec = 60

      [mcp_servers.beeper]
      url = "http://127.0.0.1:23373/v0/mcp"

    ''
  );

  readXattr = mkReadXattr codexXattr;
  writeXattr = mkWriteXattr codexXattr;

}
