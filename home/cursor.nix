{ pkgs, ... }:
let
  jsonFormat = pkgs.formats.json { };

  # Cursor reads ~/.cursor/mcp.json on startup for every CLI session. Declaring
  # it here keeps the MCP surface in-repo and reviewable.
  cursorMcp = jsonFormat.generate "cursor-mcp.json" {
    mcpServers = {
      rube = {
        url = "https://rube.composio.dev/mcp?agent=cursor";
        headers = { };
      };
      context7 = {
        command = "npx";
        args = [
          "-y"
          "@upstash/context7-mcp@latest"
        ];
      };
    };
  };
in
{
  # Cursor CLI mutates ~/.cursor/cli-config.json directly (auth, privacy cache,
  # per-session slash-command state), so we intentionally do NOT manage that
  # file here. Only MCP config is declarative.
  home.file.".cursor/mcp.json".source = cursorMcp;
}
