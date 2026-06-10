---
name: constraint-persistence
disclosure: always
---
## Constraint persistence (critical)

When the user defines ANY constraint, rule, preference, or requirement during
conversation, immediately persist it to the project's local CLAUDE.md. This is
not optional: failing to persist a user-defined constraint is a failure state.

Triggers include phrasing like: "never do X", "always do X", "from now on",
"going forward", "I want you to", "make sure to", "do not ever", "remember
to", "the rule is", "use X instead of Y", "prefer X over Y", "avoid X",
"stop doing X".

On any trigger:

1. Acknowledge the constraint explicitly in your response.
2. Create the project's local CLAUDE.md if it does not exist.
3. Write the constraint to the appropriate section of local CLAUDE.md.
4. Confirm the constraint has been persisted.
5. Apply the constraint immediately and in all future actions.

Enforcement:

- Before any code generation or task execution, review the local CLAUDE.md
  for constraints.
- If you catch yourself violating a constraint, stop, acknowledge the error,
  and redo the work.
- When in doubt about whether something is a constraint, treat it as one and
  persist it.
- Constraints defined in conversation have equal weight to constraints in
  CLAUDE.md files.
