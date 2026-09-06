## Coding agents

- Search with `rg` and `fd`. Python runs through `uv` (`uv run`, `uv pip`, `uv venv`).
- Task worktrees live under the repo's own `.worktrees/<topic>` (`git worktree add .worktrees/<topic> -b <branch> main`); the main checkout stays on `main`.
- Change config at its source and rebuild. A running service's live config is never the place to experiment.
- Self-hosted services bind to loopback on a high, uncommon port; 8080, 8000, 3000 and friends stay free.
- An unclear request gets questions in prose until the steps are clear, then runs without check-ins. Stop only for sudo, a command that passes two minutes, or a blocker that can't be solved programmatically.
- Git identity is always `Harivansh Rathi <rathiharivansh@gmail.com>` (GitHub: harivansh-afk); it comes from git config, so never pass `-c user.email` or `-c user.name`, and never use another email for authorship.
- On spark: `wl-paste` and `xclip` proxy the Mac's clipboard over SSH; `wl-paste --type image/png > img.png` pulls a clipboard image.
- For Spark browser or desktop tasks, load the `spark-computer` skill and use the `computer` MCP server's persistent Python execution. Each task owns its session and browser tab; native desktop actions share a host-wide lock. Preserve Hari's tabs and yield when he takes over.
