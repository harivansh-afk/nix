# Renders the layered agent instructions in dots/agents/ into one file per
# harness. core.md is the trunk every agent gets; the other parts are the
# deltas for one family of agents. Add a part to a list here rather than
# repeating a fact in two markdown files.
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
  hermes = render "hermes-AGENTS.md" [
    "core"
    "hermes"
  ];
}
