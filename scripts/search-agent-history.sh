#!/usr/bin/env bash
set -euo pipefail

remote="${AGENT_HISTORY_REMOTE:-netty}"
remote_root="${AGENT_HISTORY_REMOTE_ROOT:-/home/rathi/.local/share/agent-history/raw}"
initial_query="${1:-}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

remote_root_q="$(printf '%q' "$remote_root")"
initial_query_q="$(printf '%q' "$initial_query")"

ssh -t "$remote" "AGENT_HISTORY_ROOT=${remote_root_q} INITIAL_QUERY=${initial_query_q} bash -s" < "${script_dir}/search-agent-history-remote.sh"
