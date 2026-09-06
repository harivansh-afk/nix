---
name: self-evolve
description: Learn a reusable skill after solving a nontrivial task, correcting a failed workflow, or receiving feedback about how Hari works.
---

# Learn from completed work

Use Hermes' native skill tools to preserve procedures that worked in Hari's
actual tasks. This skill guides in-session learning; it does not run the separate
Nous DSPy/GEPA optimizer or observe activity outside the requested work.

1. Finish the task and verify its result first. Identify a reusable procedure,
   a surprising failure with a verified recovery, or a correction to an existing
   procedure. Skip routine answers and speculative lessons.
2. Search the skill library and read the closest matching skill with `skill_view`.
   Prefer improving that skill over creating another with the same purpose.
   Keep personal preferences in native memory; keep task status in the session.
3. Use `skill_manage` to save the smallest useful procedure: when to use it,
   prerequisites, steps, how to verify success, and any observed failure/recovery.
   Generalize task-specific names and values. Do not copy messages, account data,
   credentials, cookies, or browser profiles into skills.
4. Ground each instruction in the observed task. Record validation limits when
   a procedure has only been tried once; do not claim repeated reliability or
   measured improvement without evidence. Validate scripts with a harmless
   example when practical; do not repeat external writes just to test a skill.
5. When a later task disproves a saved step, verify the replacement and patch the
   skill. Read the saved result back to check the edit. Mention a useful new or
   corrected skill briefly when reporting the task result.

Learned skills belong in the writable skill library under `$HERMES_HOME/skills`.
Nix-owned skill files and agent guidance are changed through the nix repository's
PR workflow, not edited through store symlinks. Reuse learned skills on later
matching tasks. Do not create hooks, watchers, scheduled reviews, or a second
memory store. Creating a skill does not grant authority to carry out its actions.
