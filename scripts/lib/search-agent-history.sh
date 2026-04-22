#!/usr/bin/env bash
set -euo pipefail

remote="${AGENT_HISTORY_REMOTE:-spark}"
initial_query="${1:-}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

initial_query_q="$(printf '%q' "$initial_query")"

ssh -t "$remote" "INITIAL_QUERY=${initial_query_q} bash -s" < "${script_dir}/search-agent-history-remote.sh"
