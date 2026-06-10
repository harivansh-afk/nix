# Deploy the generated agent context (see dots/agent-context/README.md).
#
# - ~/.claude/CLAUDE.md and ~/.codex/AGENTS.md are the always-on document,
#   built from the `disclosure: always` fragments. Both tools share one core.
# - ~/.claude/skills/<name> holds the progressive-section skills plus any
#   handwritten ones. Claude Code's `/`-autocomplete discovery silently drops
#   symlinked entries (anthropics/claude-code#36659), so the skills cannot be
#   home.file symlinks into the store: seed them as real directories instead,
#   and track the managed names in a manifest so renamed or removed skills are
#   cleaned up without touching skills the user created by hand.
{
  lib,
  pkgs,
  inputs,
  ...
}:
let
  agent = import ../lib/agent-context.nix { inherit lib inputs; };
  skillsDir = agent.mkSkillsDir { inherit pkgs; };
  coreutils = "${pkgs.coreutils}/bin";
  manifest = ".nix-managed-skills";
in
{
  home.file.".claude/CLAUDE.md".text = agent.agentContext.alwaysDoc;
  home.file.".codex/AGENTS.md".text = agent.agentContext.alwaysDoc;

  home.activation.seedClaudeSkills = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    src="${skillsDir}"
    dest="$HOME/.claude/skills"
    ${coreutils}/mkdir -p "$dest"

    # Drop previously managed skills that no longer exist in the source.
    if [ -f "$dest/${manifest}" ]; then
      while IFS= read -r name; do
        [ -n "$name" ] || continue
        if [ ! -d "$src/$name" ]; then
          ${coreutils}/rm -rf "$dest/''${name:?}"
        fi
      done <"$dest/${manifest}"
    fi

    : >"$dest/${manifest}.tmp"
    for skill in "$src"/*/; do
      [ -d "$skill" ] || continue
      name="$(${coreutils}/basename "$skill")"
      ${coreutils}/rm -rf "$dest/''${name:?}"
      ${coreutils}/cp -R "$src/$name" "$dest/$name"
      ${coreutils}/chmod -R u+w "$dest/$name"
      printf '%s\n' "$name" >>"$dest/${manifest}.tmp"
    done
    ${coreutils}/mv "$dest/${manifest}.tmp" "$dest/${manifest}"
  '';
}
