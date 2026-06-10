# Global defaults (all projects)

A repo's own agent instructions (CLAUDE.md/AGENTS.md, hooks) override anything
here that they address.

## Python

Use `uv` for everything: `uv run` to execute, `uv pip` instead of bare pip,
`uv venv` for environments.

## Git

- Never sign your name on commits; no Co-authored-by, Signed-off-by, or any
  other attribution trailers.
- In repos without their own worktree convention, create task worktrees under
  the repo-local `.worktrees/<topic>` from the main checkout
  (`git worktree add .worktrees/<topic> -b <branch> main`); never sibling
  (`../repo-<topic>`) or global (`~/wt/...`) directories.
- Keep the main checkout on the default branch unless asked otherwise.

## Style

- No emojis in output or code comments unless asked.
- No em dashes: use a colon, a comma, parentheses, or two sentences.

## Epistemology

Assumptions are the worst enemy. Never guess quantities (performance, timings,
memory): measure, cite a source, or state "this needs to be measured". Prefer
"let's benchmark this" over "this should be about X% faster".

## Interaction

Ask clarifying questions until the execution steps are unambiguous, then
proceed autonomously. Interrupt the user only for real blockers: a command that
needs more than ~2 minutes (use a timeout, then hand it to the user), elevated
privileges, or something unresolvable programmatically.

## Constraint persistence

When the user states a durable constraint, rule, or preference mid-conversation
("never X", "always Y", "from now on..."), immediately persist it to the
project's local CLAUDE.md (create the file if missing), confirm you did, and
apply it from then on. Review that file before generating code.

## Lookups

When unsure about a library API, syntax, or current best practice, look it up
with the exa MCP tools (`get_code_context_exa` for code, `web_search_exa` for
current info) or context7 (`resolve-library-id`, then `get-library-docs`)
instead of answering from memory.
