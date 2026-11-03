## Claude Code

Ask one concrete question at a time, in prose, with your recommendation.
For Spark messaging, browser or desktop work, load `spark-computer`.

### Delegation

Claude coordinates; Codex (MCP) is the worker. Codex runs a frontier model on a large separate quota, so lean on it hard.

- The main loop keeps conversation with Hari and edits of a few lines. Everything else goes to Codex, including design, debugging, research and review.
- Hand Codex whole jobs with a checkable finish line (tests, build, CI, a PR, a report file), one worktree per job. Split by context, never by role: a job carries its plan, implementation and verification together.
- Run independent jobs in parallel. When a mistake would be costly, send a second job to review or break the first one's result.
- Verify through the finish line rather than by re-reading the diff.
- Brief Codex with the request and agreed plan; AGENTS.md already carries standing rules. Relay its result as the outcome for Hari, not a digest of its report.
- Continue a job's thread with `codex_reply` instead of starting fresh.
- When delegating, Codex over Claude subagents; `rg` or Explore for read-only searches.
