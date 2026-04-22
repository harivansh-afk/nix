#!/usr/bin/env bash
set -euo pipefail

remote="${AGENT_HISTORY_REMOTE:-spark}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
local_rsync="$(command -v rsync || true)"
remote_rsync="$(ssh "$remote" 'command -v rsync || true')"

if [[ -z "$local_rsync" ]]; then
  printf 'rsync is not available locally.\n' >&2
  exit 1
fi

if [[ -z "$remote_rsync" ]]; then
  printf 'rsync is not available on %s.\n' "$remote" >&2
  printf 'Install rsync on %s, then run this again.\n' "$remote" >&2
  exit 1
fi

remote_stage_root="$(
  ssh "$remote" 'mkdir -p /home/rathi/.local/share/agent-history && mktemp -d /home/rathi/.local/share/agent-history/incoming.XXXXXX'
)"
remote_stage_root="$(printf '%s' "$remote_stage_root" | tr -d '\r\n')"
remote_stage_root_q="$(printf '%q' "$remote_stage_root")"

ssh "$remote" "mkdir -p \
  ${remote_stage_root_q}/.claude \
  ${remote_stage_root_q}/.claude/transcripts \
  ${remote_stage_root_q}/.claude/projects \
  ${remote_stage_root_q}/.codex \
  ${remote_stage_root_q}/.codex/sessions \
  ${remote_stage_root_q}/.codex/memories \
  ${remote_stage_root_q}/.codex/memories/rollout_summaries"

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

sync_path "$HOME/.claude/history.jsonl" "${remote_stage_root}/.claude/"
sync_path "$HOME/.claude/transcripts/" "${remote_stage_root}/.claude/transcripts/"
sync_path "$HOME/.claude/projects/" "${remote_stage_root}/.claude/projects/"
sync_path "$HOME/.codex/history.jsonl" "${remote_stage_root}/.codex/"
sync_path "$HOME/.codex/session_index.jsonl" "${remote_stage_root}/.codex/"
sync_path "$HOME/.codex/sessions/" "${remote_stage_root}/.codex/sessions/"
sync_path "$HOME/.codex/memories/MEMORY.md" "${remote_stage_root}/.codex/memories/"
sync_path "$HOME/.codex/memories/raw_memories.md" "${remote_stage_root}/.codex/memories/"
sync_path "$HOME/.codex/memories/memory_summary.md" "${remote_stage_root}/.codex/memories/"
sync_path "$HOME/.codex/memories/rollout_summaries/" "${remote_stage_root}/.codex/memories/rollout_summaries/"

printf 'Merging staged history into %s default harness locations...\n' "$remote"
ssh "$remote" "python3 - ${remote_stage_root_q}" < "${script_dir}/merge-agent-history-remote.py"

ssh "$remote" "case ${remote_stage_root_q} in /home/rathi/.local/share/agent-history/incoming.*) rm -rf ${remote_stage_root_q} ;; *) exit 1 ;; esac"

printf 'Agent history sync complete.\n'
