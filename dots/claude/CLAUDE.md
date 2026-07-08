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

## Personal KB recall (spark only)
- Questions about my email, calendar, finances, subscriptions, repos, downloads, or reading: query the Cognee KB before saying you don't know.
- `kb-search "query"`: hybrid chunk search (pgvector HNSW + Postgres full-text, RRF-fused; no LLM, ~0.5s). First choice for any lookup; handles rare terms and one-word queries via the lexical arm.
- `kb-graph resolve|neighbors|connect|source "<entity>"`: read-only graph traversal (no sudo, prints JSON). Use for relation questions: who connects to what, path between two entities, source chunks behind an entity.
- Graph store via first-party CLI: `sudo cognee-env /var/lib/cognee/venv/bin/cognee-cli search -t CHUNKS -d <dataset> -k 15 -f simple "query"`. Datasets: gmail, calendar, finance, forgejo, downloads, loops, research. Types: CHUNKS (raw retrieval, no LLM: prefer this and synthesize yourself), GRAPH_COMPLETION (default: seeds from only the top-k vector hits, k defaults to 5 triplets, then a strict small-brain answer; says "No information found" whenever the seeds miss - always pass `-k 15`+), RAG_COMPLETION, SUMMARIES. Use `-f json` for parseable output.
- Iterate: reformulate and re-query rather than trusting one retrieval pass.

## Clipboard image
- When the user refers to an image/screenshot "in my clipboard" (it lives on their Mac), run `pasteimg` to pull it here as a PNG, then Read the printed path.
