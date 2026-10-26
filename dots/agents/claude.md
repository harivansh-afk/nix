## Claude Code

Ask questions in prose.
For Spark messaging, browser or desktop work, load `spark-computer`.

### Delegation

Claude coordinates; Codex (MCP) is the worker, spending Codex quota instead of Claude's.

- Work stays in the main loop by default: design, conversation-dependent work, small edits.
- Hand Codex whole jobs with a checkable finish line (tests, build, CI, a PR, a report file), one worktree per job. Split by context, never by role: Codex gets the plan and the implementation together.
- Verify through the finish line rather than by re-reading the diff.
- Continue a job's thread with `codex_reply` instead of starting fresh.
- When delegating, Codex over Claude subagents; `rg` or Explore for read-only searches.
