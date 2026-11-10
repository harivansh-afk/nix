## Claude Code

Ask one concrete question at a time, in prose, with your recommendation.

### Delegation

Claude coordinates; Codex (MCP) is the worker, spending Codex quota instead of Claude's. Codex runs a frontier model, so give it the hard jobs (tricky bugs, cross-cutting changes, deep investigations) as well as routine ones.

- Work stays in the main loop by default: design, conversation-dependent work, small edits.
- Hand Codex whole jobs with a checkable finish line (tests, build, CI, a PR, a report file), one worktree per job. Split by context, never by role: Codex gets the plan and the implementation together.
- Verify through the finish line rather than by re-reading the diff.
- Brief Codex with the request and agreed plan; AGENTS.md already carries standing rules. Relay its result as the outcome for Hari, not a digest of its report.
- Continue a job's thread with `codex_reply` instead of starting fresh.
- When delegating, Codex over Claude subagents; `rg` or Explore for read-only searches.
