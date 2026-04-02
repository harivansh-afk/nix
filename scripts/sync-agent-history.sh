#!/usr/bin/env bash
set -euo pipefail

remote="${AGENT_HISTORY_REMOTE:-netty}"
remote_root="${AGENT_HISTORY_REMOTE_ROOT:-/home/rathi/.local/share/agent-history/raw/darwin}"
local_rsync="$(command -v rsync || true)"
remote_rsync="$(ssh "$remote" 'command -v rsync || true')"

if [[ -z "$local_rsync" ]]; then
  printf 'rsync is not available locally.\n' >&2
  exit 1
fi

if [[ -z "$remote_rsync" ]]; then
  printf 'rsync is not available on %s.\n' "$remote" >&2
  printf 'Deploy netty after adding rsync to the package set, then run this again.\n' >&2
  exit 1
fi

remote_root_q="$(printf '%q' "$remote_root")"

ssh "$remote" "mkdir -p \
  ${remote_root_q}/claude \
  ${remote_root_q}/claude/transcripts \
  ${remote_root_q}/claude/projects \
  ${remote_root_q}/codex \
  ${remote_root_q}/codex/sessions"

sync_path() {
  local src="$1"
  local dest="$2"

  if [[ ! -e "$src" ]]; then
    printf 'Skipping missing path: %s\n' "$src"
    return
  fi

  printf 'Syncing %s -> %s:%s\n' "$src" "$remote" "$dest"
  "$local_rsync" -az --rsync-path="$remote_rsync" "$src" "$remote:$dest"
}

sync_path "$HOME/.claude/history.jsonl" "${remote_root}/claude/"
sync_path "$HOME/.claude/transcripts/" "${remote_root}/claude/transcripts/"
sync_path "$HOME/.claude/projects/" "${remote_root}/claude/projects/"
sync_path "$HOME/.codex/history.jsonl" "${remote_root}/codex/"
sync_path "$HOME/.codex/session_index.jsonl" "${remote_root}/codex/"
sync_path "$HOME/.codex/sessions/" "${remote_root}/codex/sessions/"

printf 'Agent history sync complete.\n'
