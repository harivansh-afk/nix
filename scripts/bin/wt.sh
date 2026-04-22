#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage:
  wt create <worktree-name>
  wt remove
  wt prune
EOF
  exit 1
}

current_worktree_root=
main_repo_root=

resolve_repo_context() {
  local common_git_dir

  current_worktree_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
    printf 'wt: not inside a git repository\n' >&2
    exit 1
  }

  common_git_dir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || {
    printf 'wt: failed to resolve common git directory\n' >&2
    exit 1
  }

  main_repo_root=$(cd "${common_git_dir}/.." && pwd -P) || {
    printf 'wt: failed to resolve repository root\n' >&2
    exit 1
  }
}

sanitize_name() {
  local clean_name

  clean_name=$(printf '%s' "$1" | sed -E 's#[^[:alnum:]._-]+#-#g; s#-+#-#g; s#(^[.-]+|[.-]+$)##g')

  if [[ -z "$clean_name" ]]; then
    printf 'wt: %s does not produce a usable path name\n' "$1" >&2
    exit 1
  fi

  printf '%s\n' "$clean_name"
}

target_path_for() {
  local clean_name repo_name repo_parent

  clean_name=$(sanitize_name "$1")
  repo_parent=$(dirname "$main_repo_root")
  repo_name=$(basename "$main_repo_root")

  printf '%s/%s-%s\n' "$repo_parent" "$repo_name" "$clean_name"
}

resolve_main_ref() {
  if git -C "$main_repo_root" show-ref --verify --quiet refs/heads/main; then
    printf 'main\n'
    return
  fi

  if git -C "$main_repo_root" symbolic-ref -q --short refs/remotes/origin/HEAD >/dev/null; then
    git -C "$main_repo_root" symbolic-ref -q --short refs/remotes/origin/HEAD | sed 's#^origin/##'
    return
  fi

  if git -C "$main_repo_root" symbolic-ref -q --short HEAD >/dev/null; then
    git -C "$main_repo_root" symbolic-ref -q --short HEAD
    return
  fi

  printf 'wt prune: could not resolve the primary branch\n' >&2
  exit 1
}

worktree_is_clean() {
  [[ -z "$(git -C "$1" status --porcelain --untracked-files=normal 2>/dev/null)" ]]
}

create_worktree() {
  local branch_name target_path

  [[ $# -eq 1 ]] || usage

  branch_name=$1
  target_path=$(target_path_for "$branch_name")

  if [[ -e "$target_path" ]]; then
    printf 'wt create: path already exists: %s\n' "$target_path" >&2
    exit 1
  fi

  if git -C "$current_worktree_root" show-ref --verify --quiet "refs/heads/$branch_name"; then
    git -C "$current_worktree_root" worktree add -- "$target_path" "$branch_name" 1>&2
  else
    git -C "$current_worktree_root" worktree add -b "$branch_name" -- "$target_path" HEAD 1>&2
  fi

  printf '%s\n' "$target_path"
}

remove_current_worktree() {
  [[ $# -eq 0 ]] || usage

  if [[ "$current_worktree_root" == "$main_repo_root" ]]; then
    printf 'wt remove: not inside a linked worktree\n' >&2
    exit 1
  fi

  git -C "$main_repo_root" worktree remove "$current_worktree_root" 1>&2
  printf '%s\n' "$current_worktree_root"
}

prune_worktree() {
  local path=$1
  local main_commit=$2
  local current_commit

  if [[ "$path" == "$main_repo_root" || "$path" == "$current_worktree_root" ]]; then
    return 1
  fi

  if ! worktree_is_clean "$path"; then
    return 1
  fi

  current_commit=$(git -C "$path" rev-parse HEAD 2>/dev/null) || return 1

  if [[ "$current_commit" != "$main_commit" ]]; then
    return 1
  fi

  git -C "$main_repo_root" worktree remove "$path" 1>&2
  printf '%s\n' "$path"
  return 0
}

prune_worktrees() {
  local line main_commit main_ref path removed_any=0

  [[ $# -eq 0 ]] || usage

  main_ref=$(resolve_main_ref)
  main_commit=$(git -C "$main_repo_root" rev-parse "$main_ref")
  path=

  while IFS= read -r line; do
    case "$line" in
      worktree\ *)
        path=${line#worktree }
        ;;
      "")
        if [[ -n "$path" ]] && prune_worktree "$path" "$main_commit"; then
          removed_any=1
        fi
        path=
        ;;
    esac
  done < <(git -C "$main_repo_root" worktree list --porcelain && printf '\n')

  git -C "$main_repo_root" worktree prune 1>&2

  if [[ $removed_any -eq 0 ]]; then
    printf 'wt prune: no removable worktrees found\n' >&2
  fi
}

resolve_repo_context

case "${1:-}" in
  create)
    shift
    create_worktree "$@"
    ;;
  remove)
    shift
    remove_current_worktree "$@"
    ;;
  prune)
    shift
    prune_worktrees "$@"
    ;;
  *)
    usage
    ;;
esac
