{
  lib,
  homeDirectory,
  pkgs,
  hostname,
  isDarwin,
  skillSources,
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

  delegateToCodex = hostname == "spark";
  codexMcp = import ../../../pkgs/codex-mcp { inherit pkgs; };

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
          codex = {
            type = "stdio";
            command = "${codexMcp}/bin/codex-mcp";
            timeout = 14400000;
          };
        }
      )
    else
      null;

  claudeSettings = jsonFormat.generate "claude-settings.json" {
    "$schema" = "https://json.schemastore.org/claude-code-settings.json";
    env =
      if delegateToCodex then
        { CLAUDE_CODE_MCP_AUTO_BACKGROUND_MS = "10000"; }
      else
        { CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1"; };
    model = "claude-fable-5-1";
    tui = "fullscreen";
    permissions = {
      defaultMode = "bypassPermissions";
      deny = [
        "Artifact"
        "ArtifactComments"
        "ArtifactData"
        "AskUserQuestion"
        "CronCreate"
        "CronDelete"
        "CronList"
        "DesignSync"
        "EnterWorktree"
        "ExitWorktree"
        "ScheduleWakeup"
        "SendFeedback"
      ]
      ++ lib.optionals delegateToCodex [ "Workflow" ];
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
  };

  codexConfigSource = pkgs.writeText "codex-config.toml" (
    lib.optionalString (hostname == "spark") ''
      model_provider = "codex-lb"
      mcp_oauth_credentials_store = "file"
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

      [mcp_servers.computer]
      command = "${computer.servers.computer.command}"
      startup_timeout_sec = 20
      tool_timeout_sec = 60

      [mcp_servers.beeper]
      url = "http://127.0.0.1:23373/v0/mcp"
      startup_timeout_sec = 20

    ''
  );

  readXattr = mkReadXattr codexXattr;
  writeXattr = mkWriteXattr codexXattr;

}
