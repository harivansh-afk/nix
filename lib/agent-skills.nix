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
      name = "deepen";
      path = ../dots/agents/skills/deepen;
    }
    {
      name = "maintainable-code";
      path = ../dots/agents/skills/maintainable-code;
    }
    {
      name = "technical-writing";
      path = ../dots/agents/skills/technical-writing;
    }
  ]
)
