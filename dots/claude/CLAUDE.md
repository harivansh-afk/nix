# Global instructions

## Python
- Use `uv` for everything: `uv run`, `uv pip`, `uv venv`. Never bare `pip`.

## Style
- No emojis. No em dashes (use `-` or `:`).

## Git
- Never sign commits. No `Co-authored-by`/`Signed-off-by`/any attribution.
- Worktrees go under repo-local `.worktrees/<topic>`; create with `git worktree add .worktrees/<topic> -b <branch> main`. Never sibling/global dirs. Keep main checkout on `main` unless asked.

## Epistemology
- Assumptions are the enemy. Never guess numbers (perf, timings, memory). Measure it, cite a source, or say "needs to be measured". Prefer "let's benchmark" over guessed percentages.

## Interaction
- If a request is unclear, ask until steps are clear; then proceed autonomously.
- Only stop for help when: a script runs >2min (timeout, then ask), sudo is needed, or a hard blocker can't be solved programmatically.

## Constraint persistence (critical)
- When the user states any rule/preference/constraint, immediately persist it to the project's local CLAUDE.md, acknowledge it, and apply it from then on. Not persisting a stated constraint is a failure.

## MCP / lookups
- Unsure about an API/syntax/best practice: use an MCP server before guessing.
- exa `get_code_context_exa` for library/API/SDK questions; exa `web_search_exa` for current info; context7 (`resolve-library-id` then `get-library-docs`) for library docs.

## Clipboard image
- When the user refers to an image/screenshot "in my clipboard" (it lives on their Mac), run `pasteimg` to pull it here as a PNG, then Read the printed path.
