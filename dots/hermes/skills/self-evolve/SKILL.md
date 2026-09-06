---
name: self-evolve
description: Turn a verified reusable workflow or correction into a declarative Nix skill PR.
---

# Learn through skill PRs

After verified work, save only useful, repeatable lessons. Reuse or improve an
existing skill before adding one. Keep instructions short and evidence-based.

Follow the Nix repo's AGENTS.md. In a task worktree, write
`dots/hermes/skills/<name>/SKILL.md` and any supporting files, validate the change,
and open a PR at https://git.harivan.sh/harivansh-afk/nix with tea. Nix discovers
these directories automatically. Do not shadow cua-driver or write runtime skills
with skill_manage. Keep private data and credentials out of the repo.

Share the PR link and checks. Follow the merge/clarify policy in Hermes' AGENTS.md;
report proposed, merged and deployed status accurately. Future corrections use
the same PR path. Do not add background scanners, hooks or scheduled reviews.
