#!/usr/bin/env bash
# PreToolUse[Agent|Task]: subagents become herdr panes with forked context.
#
# Instead of the built-in in-process subagent, fork the parent session's
# full context (claude --resume <sid> --fork-session) into a fresh agent
# running in a new pane of the same herdr window. The parent is told where
# the pane is and how to check on it; the human can just read the pane.
#
# Falls through to the normal Agent tool (exit 0) outside herdr, when
# disabled via CLAUDE_SUBAGENT_PANES=0, or when the spawn fails.
set -uo pipefail

input=$(cat)

[ "${CLAUDE_SUBAGENT_PANES:-1}" = "0" ] && exit 0
[ -n "${HERDR_PANE_ID:-}" ] || exit 0
command -v herdr >/dev/null 2>&1 || exit 0
herdr status server >/dev/null 2>&1 || exit 0

session_id=$(jq -r '.session_id // empty' <<<"$input")
cwd=$(jq -r '.cwd // empty' <<<"$input")
desc=$(jq -r '.tool_input.description // "subagent"' <<<"$input")
prompt=$(jq -r '.tool_input.prompt // empty' <<<"$input")
model=${CLAUDE_SUBAGENT_MODEL:-opus}

[ -n "$session_id" ] || exit 0
[ -n "$prompt" ] || exit 0

# The task prompt goes through a file: send-text cannot safely carry
# multi-line prompts (a newline would submit mid-prompt).
taskdir="$HOME/.claude/scratch/subagent-tasks"
mkdir -p "$taskdir"
task_file=$(mktemp "$taskdir/task-XXXXXX.md")
printf '%s\n' "$prompt" >"$task_file"

# Tile, don't stack: the first subagent splits right of the parent; each
# later one splits off the previously spawned subagent pane, alternating
# down/right, so many subagents spiral into a grid instead of slicing the
# parent into slivers. Spawn order per parent session lives in a state
# file; flock serializes concurrent Agent calls through pane selection.
statefile="$taskdir/panes-$session_id"
exec 9>"$statefile.lock"
flock 9
count=0
last=""
[ -f "$statefile" ] && read -r count last <"$statefile"
target=$HERDR_PANE_ID
direction=right
ratio=0.38
if [ -n "$last" ] && herdr pane get "$last" >/dev/null 2>&1; then
  target=$last
  ratio=0.5
  [ $((count % 2)) -eq 1 ] && direction=down || direction=right
else
  count=0
fi
split_args=("$target" --direction "$direction" --ratio "$ratio" --no-focus)
[ -n "$cwd" ] && split_args+=(--cwd "$cwd")
pane=$(herdr pane split "${split_args[@]}" 2>/dev/null | jq -r '.result.pane.pane_id // empty')
if [ -z "$pane" ]; then
  flock -u 9
  exit 0
fi
echo "$((count + 1)) $pane" >"$statefile"
flock -u 9

fail() {
  herdr pane close "$pane" >/dev/null 2>&1
  exit 0
}

herdr pane run "$pane" "claude --resume $session_id --fork-session --model $model" >/dev/null 2>&1 || fail

# The bypass-permissions disclaimer shows on every launch; accept it.
# Settle delays matter: keys sent while the dialog is still rendering are
# dropped and a later Enter would land on "No, exit".
if herdr pane wait-output "$pane" --match 'Yes, I accept' --timeout 20000 >/dev/null 2>&1; then
  sleep 2
  herdr pane send-keys "$pane" 2 >/dev/null 2>&1
  sleep 1
  herdr pane send-keys "$pane" Enter >/dev/null 2>&1
fi

herdr pane wait-output "$pane" --match 'bypass permissions on' --timeout 120000 >/dev/null 2>&1 || fail

herdr pane rename "$pane" "sub: $desc" >/dev/null 2>&1

herdr pane send-text "$pane" "You are a subagent forked from the parent session's context: you remember the conversation so far. Read $task_file and complete the task it describes. Work in this pane; the parent agent and the human read your output here." >/dev/null 2>&1 || fail
sleep 1
herdr pane send-keys "$pane" Enter >/dev/null 2>&1

reason="Not an error: this host replaces in-process subagents with herdr panes. \"$desc\" is now running as a $model agent forked from this session's full context, in pane $pane of this window. Check on it with: \`herdr agent wait $pane --timeout <ms>\` (block until its turn settles), \`herdr pane read $pane\` (read its output), \`herdr agent prompt $pane \"<text>\"\` (send follow-ups). Do not retry the Agent tool for this task."
jq -n --arg reason "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $reason
  }
}'
