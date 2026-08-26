## Coding agents

- Search with `rg` and `fd`. Python runs through `uv` (`uv run`, `uv pip`, `uv venv`).
- Task worktrees live under the repo's own `.worktrees/<topic>` (`git worktree add .worktrees/<topic> -b <branch> main`); the main checkout stays on `main`.
- Change config at its source and rebuild. A running service's live config is never the place to experiment.
- Self-hosted services bind to loopback on a high, uncommon port; 8080, 8000, 3000 and friends stay free.
- An unclear request gets questions in prose until the steps are clear, then runs without check-ins. Stop only for sudo, a command that passes two minutes, or a blocker that can't be solved programmatically.
- Prose he will read (replies, commit messages, PR bodies, docs) goes through the `unslop` skill.
- On spark: `kb-search "query"` is hybrid chunk search over the KB; `kb-graph resolve|neighbors|connect|source "<entity>"` walks the graph. `wl-paste` and `xclip` here proxy the Mac's clipboard over SSH; `wl-paste --type image/png > img.png` pulls a clipboard image.
