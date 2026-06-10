# Agent context

Single source for the instructions delivered to coding agents (Claude Code and
Codex) on both hosts. The committed files here are markdown fragments; the
deployed `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md` are generated from them
at build time by `lib/agent-context.nix`, which reuses the agent-context
builders from the `index` flake input (`indexable-inc/index`).

## Disclosure tiers

Each file in [`sections/`](sections) is one fragment with YAML frontmatter:

```yaml
---
name: python-uv
disclosure: progressive   # always | progressive
description: "Python tooling defaults. Use when writing or running Python."
---
## Python
...
```

- `disclosure: always` fragments are concatenated (in file order) into the
  always-on document that becomes `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md`.
  The total size is a build-time invariant (`alwaysCharCap` in the index lib):
  marking too much `always` fails `nix build` instead of silently bloating
  every session's context.
- `disclosure: progressive` fragments each become a Claude Code skill under
  `~/.claude/skills/<name>/SKILL.md`. Only the `name` + `description` stay
  always-visible; the body loads on demand. Write `description` as
  "what this covers; use when ...": it is the trigger Claude uses to decide
  when to load the skill.

Handwritten skills (a directory with a `SKILL.md`) can be dropped into
[`skills/`](skills); they are auto-discovered and merged with the generated
ones.

## Preview

```sh
nix build .#claude-md --no-link --print-out-paths | xargs cat
nix build .#codex-md  --no-link --print-out-paths | xargs cat
nix build .#agent-skills --no-link --print-out-paths | xargs ls
```
