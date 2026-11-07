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
in
lib.optionals (mattpocock != null) (
  map pocock [
    "productivity/writing-for-agents"
    "engineering/research"
  ]
)
++ lib.optionals spark [
  {
    name = "spark-computer";
    path = ../dots/agents/skills/spark-computer;
  }
  {
    name = "webjit";
    path = "${pkgs.webjit}/share/webjit/skills/webjit";
  }
]
++ [
  {
    name = "crux";
    path = ../dots/agents/skills/crux;
  }
]
