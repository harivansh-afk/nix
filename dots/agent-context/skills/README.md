# Handwritten skills

Each subdirectory here is a Claude Code skill: a directory containing a
`SKILL.md` (with `name` and `description` frontmatter) and optionally
`assets/` and `references/`. Skills are auto-discovered by
`lib/agent-context.nix` and merged with the generated progressive-section
skills into `~/.claude/skills`.

Plain files in this directory (like this README) are ignored; only
subdirectories count as skills.
