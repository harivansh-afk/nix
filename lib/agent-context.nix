# Agent context, reusing the builders from the `index` flake input
# (indexable-inc/index, already an input for the pi-harness) instead of
# vendoring them. The fragments live in dots/agent-context/sections; see the
# README there for the disclosure-tier model.
#
# The index lib asserts two invariants at build time:
# - the always-on document stays under its char cap (alwaysCharCap), so
#   marking too much `disclosure: always` fails the build loudly;
# - the skills directory contains no symlinks, because Claude Code's
#   `/`-autocomplete discovery silently drops symlinked entries
#   (anthropics/claude-code#36659).
#
# If a flake.lock update moves index's internal layout, the agent-context
# flake check fails and the weekly lock-update PR surfaces it.
{ lib, inputs }:
let
  agentContext = import (inputs.index + "/lib/agent-context") {
    inherit lib;
    paths.agentContext = ../dots/agent-context;
  };

  skills = import (inputs.index + "/lib/agent-context/skills.nix") {
    inherit lib;
    paths.skills = ../dots/agent-context/skills;
  };
in
{
  inherit agentContext skills;

  # One directory holding every skill: handwritten ones from
  # dots/agent-context/skills plus a generated skill per
  # `disclosure: progressive` section. Built symlink-free; deliver it by
  # copying, not symlinking (see home/agent-context.nix).
  mkSkillsDir =
    { pkgs }:
    skills.mkSkillsDir {
      inherit pkgs;
      extraSkills = agentContext.mkProgressiveSkills { inherit pkgs; };
    };
}
