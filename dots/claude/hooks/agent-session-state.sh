#!/usr/bin/env bash
# Maintains a per-session state file so editors can map live agent sessions to
# the directory (worktree) they are working in, and pokes a listening neovim.
#
# Wired to SessionStart, PostToolUse, Stop, and SessionEnd for both claude and
# codex (codex consumes the same hooks via /etc/codex/requirements.toml).
#
# State:  $XDG_STATE_HOME/agent-sessions/<session_id>.json
#         { session_id, agent, host, event, cwd, worktree, branch, ts }
# Poke:   nvim --server $XDG_CACHE_HOME/nvim/agentdiff.sock (fire-and-forget;
#         the editor is latency sugar, git + the state dir are the truth)
set -u

INPUT=$(cat)
sid=$(echo "$INPUT" | jq -r '.session_id // empty')
evt=$(echo "$INPUT" | jq -r '.hook_event_name // empty')
[ -n "$sid" ] || exit 0

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/agent-sessions"
sock="${XDG_CACHE_HOME:-$HOME/.cache}/nvim/agentdiff.sock"

poke() {
  [ -S "$sock" ] || return 0
  command -v nvim >/dev/null 2>&1 || return 0
  arg=$(printf '%s' "$1" | jq -Rs .)
  nvim --server "$sock" --remote-expr \
    "v:lua.require'agentdiff'.poke($arg)" >/dev/null 2>&1 &
}

if [ "$evt" = "SessionEnd" ]; then
  rm -f "$state_dir/$sid.json"
  poke ""
  exit 0
fi

mkdir -p "$state_dir"

# Ground truth for "where is the work": the edited file's directory when the
# event carries one (Edit/Write/NotebookEdit), otherwise the session cwd.
path=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')
if [ -n "$path" ]; then
  dir=$(dirname -- "$path")
else
  dir=$(echo "$INPUT" | jq -r '.cwd // empty')
fi
[ -d "$dir" ] || dir=$HOME

worktree=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)
branch=""
if [ -n "$worktree" ]; then
  branch=$(git -C "$worktree" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
fi

agent="claude"
[ -n "${CODEX_PROJECT_DIR:-}" ] && agent="codex"

cwd=$(echo "$INPUT" | jq -r '.cwd // empty')
tmp="$state_dir/$sid.json.tmp"
jq -n \
  --arg sid "$sid" --arg agent "$agent" --arg host "$(hostname)" \
  --arg evt "$evt" --arg cwd "$cwd" --arg worktree "$worktree" \
  --arg branch "$branch" --argjson ts "$(date +%s)" \
  '{session_id: $sid, agent: $agent, host: $host, event: $evt,
    cwd: $cwd, worktree: $worktree, branch: $branch, ts: $ts}' \
  > "$tmp" && mv "$tmp" "$state_dir/$sid.json"

poke "$worktree"
exit 0
