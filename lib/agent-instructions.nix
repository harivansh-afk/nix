{ pkgs }:
let
  inherit (pkgs) lib;
  part = name: builtins.readFile (../dots/agents + "/${name}.md");
  render = file: parts: pkgs.writeText file (lib.concatStringsSep "\n" (map part parts));
in
{
  claude = render "CLAUDE.md" [
    "core"
    "coding"
    "claude"
  ];
  codex = render "AGENTS.md" [
    "core"
    "coding"
  ];
}
