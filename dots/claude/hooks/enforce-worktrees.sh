#!/usr/bin/env bash
# PreToolUse (Edit|Write|NotebookEdit): deny file writes inside a repo's MAIN
# checkout. Task work belongs in a worktree (.worktrees/<topic> or tmpfs);
# linked worktrees are always allowed, non-repo paths are always allowed.
#
# Escape hatch: HOOK_ALLOW_MAIN_CHECKOUT=1 in the environment.
set -uo pipefail

[ "${HOOK_ALLOW_MAIN_CHECKOUT:-0}" = "1" ] && exit 0

INPUT=$(cat)
path=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')
[ -n "$path" ] || exit 0

# Walk up to an existing directory (the write may create new subdirs).
dir=$(dirname -- "$path")
while [ ! -d "$dir" ] && [ "$dir" != "/" ]; do
  dir=$(dirname -- "$dir")
done

gitdir=$(git -C "$dir" rev-parse --absolute-git-dir 2>/dev/null) || exit 0
common=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0

# Linked worktrees have git-dir = <main>/.git/worktrees/<name> while the
# common dir stays <main>/.git; only in the main checkout are they equal.
[ "$gitdir" = "$common" ] || exit 0

toplevel=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || exit 0

jq -n --arg reason "Writes in the main checkout ($toplevel) are blocked. Create a task worktree first: git worktree add .worktrees/<topic> -b <branch> main, then edit there. (Escape hatch: HOOK_ALLOW_MAIN_CHECKOUT=1.)" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $reason
  }
}'
exit 0
