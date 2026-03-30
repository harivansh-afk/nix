#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'usage: wt-path <worktree-name>\n' >&2
  exit 1
fi

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'wt-path: not inside a git repository\n' >&2
  exit 1
}

worktree_name=$1
clean_name=$(printf '%s' "$worktree_name" | sed -E 's#[^[:alnum:]._-]+#-#g; s#-+#-#g; s#(^[.-]+|[.-]+$)##g')

if [[ -z "$clean_name" ]]; then
  printf 'wt-path: %s does not produce a usable path name\n' "$worktree_name" >&2
  exit 1
fi

repo_parent=$(dirname "$repo_root")
repo_name=$(basename "$repo_root")

printf '%s/%s-%s\n' "$repo_parent" "$repo_name" "$clean_name"
