# Skills that every agent harness gets: linked into ~/.agents/skills and
# ~/.claude/skills, and handed to Hermes as an external skills dir.
{
  pkgs,
  mattpocock ? null,
  spark ? false,
}:
let
  inherit (pkgs) lib;
  pocock = rel: {
    name = baseNameOf rel;
    path = "${mattpocock}/skills/${rel}";
  };
  invocable =
    skill:
    skill
    // {
      path = pkgs.runCommand "skill-${skill.name}" { } ''
        cp -r ${skill.path} $out
        chmod -R u+w $out
        sed -i '/^disable-model-invocation:/d' $out/SKILL.md
      '';
    };
in
map invocable (
  lib.optionals (mattpocock != null) (
    map pocock [
      "productivity/writing-for-agents"
      "engineering/research"
      "productivity/wait-what"
    ]
  )
  ++ lib.optionals spark [
    {
      name = "agent-browser";
      path = "${pkgs.agent-browser}/skills/agent-browser";
    }
  ]
  ++ [
    {
      name = "crux";
      path = ../dots/agents/skills/crux;
    }
    {
      name = "maintainable-code";
      path = ../dots/agents/skills/maintainable-code;
    }
  ]
)
