## Claude Code

Ask questions in prose.

## Delegating to Codex on Spark

On Spark, Claude's built-in subagents are disabled. Hand substantial work to Codex instead: implementation, debugging, research, or a second opinion. Codex runs `gpt-6-astra` unless the task needs `--model` or `--effort`.

1. Write the brief to a file, then start Codex with Bash `run_in_background: true`:
   `timeout 2h node "$CODEX_COMPANION" task --write --prompt-file /tmp/codex-<topic>.md`
   Drop `--write` for read-only work. Start parallel tasks in one message.
2. Codex has none of your context. State the goal, the relevant paths, the constraints, what done looks like, and what to report back: changes made, verification run, open questions. Parallel tasks share the checkout, so give each one separate files or tell it where the others are working.
3. Keep working or end the turn. The completion notification carries Codex's final report; don't poll.
4. Check the claims before you rely on them: read the diff and rerun the verification.
5. `task --resume-last --write --prompt-file ...` continues the latest Codex thread. `node "$CODEX_COMPANION" status`, `result <job>`, and `cancel <job>` manage jobs; `/codex:review` reviews the working tree.
