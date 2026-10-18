{
  lib,
  pkgs,
  homeDirectory,
  hostname,
  isDarwin,
  skillSources,
  ...
}:
let
  agentInstructions = import ../../../lib/agent-instructions.nix { inherit pkgs; };
  computer = import ../../../pkgs/computer-tools { inherit pkgs; };

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

in
{
  claudeMd = agentInstructions.claude;
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

  claudeSettings = jsonFormat.generate "claude-settings.json" {
    "$schema" = "https://json.schemastore.org/claude-code-settings.json";
    env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
    model = "claude-fable-5-1";
    tui = "fullscreen";
    permissions.defaultMode = "bypassPermissions";
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
    builtins.readFile ../../../dots/codex/config.toml
    + lib.optionalString (hostname == "spark") ''

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
