# Agent-context outputs: preview packages and the build-time gate.
#
# `nix build .#claude-md` / `.#codex-md` print the always-on document that
# home/agent-context.nix deploys to ~/.claude/CLAUDE.md and ~/.codex/AGENTS.md;
# `.#agent-skills` is the merged skills directory. The check forces both, so
# `nix flake check` fails if the always tier overflows its char cap or a
# skill ships a symlink.
{ inputs, lib, ... }:
let
  agent = import ../lib/agent-context.nix { inherit lib inputs; };
in
{
  perSystem =
    { pkgs, ... }:
    let
      claudeMd = pkgs.writeText "CLAUDE.md" agent.agentContext.alwaysDoc;
      codexMd = pkgs.writeText "AGENTS.md" agent.agentContext.alwaysDoc;
      agentSkills = agent.mkSkillsDir { inherit pkgs; };
    in
    {
      packages = {
        claude-md = claudeMd;
        codex-md = codexMd;
        agent-skills = agentSkills;
      };

      checks.agent-context = pkgs.runCommand "agent-context-check" { } ''
        test -s ${claudeMd}
        test -s ${codexMd}
        test -d ${agentSkills}
        touch $out
      '';
    };
}
