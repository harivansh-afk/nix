#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'usage: wt-create <worktree-name>\n' >&2
  exit 1
fi

branch_name=$1
repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'wt-create: not inside a git repository\n' >&2
  exit 1
}

target_path=$(wt-path "$branch_name")

if [[ -e "$target_path" ]]; then
  printf 'wt-create: path already exists: %s\n' "$target_path" >&2
  exit 1
fi

if git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch_name"; then
  git -C "$repo_root" worktree add -- "$target_path" "$branch_name" 1>&2
else
  git -C "$repo_root" worktree add -b "$branch_name" -- "$target_path" HEAD 1>&2
fi

printf '%s\n' "$target_path"
