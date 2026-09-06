---
name: self-evolve
description: Propose a declarative Nix skill after solving a nontrivial task, correcting a failed workflow, or receiving feedback about how Hari works.
---

# Learn through skill PRs

Preserve verified procedures in https://git.harivan.sh/harivansh-afk/nix. This
skill guides learning from requested work; it does not run the separate Nous
DSPy/GEPA optimizer or observe unrelated activity.

1. Finish and verify the task. Identify a reusable procedure or a verified
   correction. Skip routine answers and speculative lessons.
2. Search existing skills with `skill_view` and inspect dots/hermes/skills in the
   Nix repo. Improve an existing skill when it already covers the task. For a
   bundled skill, make a deliberate repo-owned override instead of modifying the
   installed copy. Never shadow the separately managed cua-driver skill.
3. Follow the repo's AGENTS.md. Keep main on main; create a task worktree under
   .worktrees. Write dots/hermes/skills/<name>/SKILL.md with name and description
   frontmatter, trigger, prerequisites, steps and success checks. Nix discovers
   each directory containing SKILL.md automatically. Put supporting files inside
   that directory. Do not use skill_manage to create or edit the runtime copy.
4. Keep generalizable instructions grounded in the observed task. Exclude
   private messages, account data, credentials and browser state. Record limits
   of the evidence; do not claim repeated reliability after one successful run.
   Validate scripts with harmless examples without repeating external writes.
5. Run formatting, git diff --check and relevant checks, including Spark Nix
   evaluation for skill wiring. Commit and push; use tea to open a PR against main
   on harivansh-afk/nix. Verify the rendered description and CI status. Explain the
   trigger, the lesson and the validation in the PR.
6. Send Hari the PR link, concise change summary and checks. Follow the merge
   authorization rules in AGENTS.md: use existing scoped authorization, otherwise
   ask for yes/no identifying the PR. Wait for the answer before merging. A no
   leaves the PR unmerged. Do not force-merge.
7. After an authorized merge, check deployment and confirm the skill is linked
   and readable in Hermes. Until then, report it as proposed, not installed.

Later corrections follow the same PR path. Long-lived behavior, plugins and
configuration also belong in Nix. Personal runtime memory remains private and
does not substitute for a declarative skill. Do not add hooks, watchers or
scheduled reviews. A saved skill does not grant permission to perform its steps.
