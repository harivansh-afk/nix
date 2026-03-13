#!/usr/bin/env bash
set -euo pipefail

umask 077

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
backup_root="${repo_root}/private-backup"
timestamp="$(date +%Y%m%d-%H%M%S)"
backup_dir="${1:-${backup_root}/${timestamp}}"

mkdir -p "${backup_dir}/archives" "${backup_dir}/manifests"

snapshot_log="$(tmutil localsnapshot 2>&1 || true)"
printf '%s\n' "${snapshot_log}" > "${backup_dir}/manifests/apfs-localsnapshot.log"
tmutil listlocalsnapshots / > "${backup_dir}/manifests/apfs-localsnapshots.txt" 2>&1 || true

{
  printf 'created_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'hostname=%s\n' "$(scutil --get HostName 2>/dev/null || hostname)"
  printf 'local_host_name=%s\n' "$(scutil --get LocalHostName 2>/dev/null || true)"
  printf 'computer_name=%s\n' "$(scutil --get ComputerName 2>/dev/null || true)"
  printf 'repo_root=%s\n' "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
} > "${backup_dir}/manifests/backup-meta.txt"

sw_vers > "${backup_dir}/manifests/sw_vers.txt"
uname -a > "${backup_dir}/manifests/uname.txt"
df -h / /System/Volumes/Data /nix > "${backup_dir}/manifests/disk-usage.txt"

if command -v brew >/dev/null 2>&1; then
  brew bundle dump --file=- --force --describe > "${backup_dir}/manifests/Brewfile" 2> "${backup_dir}/manifests/brew-bundle.stderr" || true
  brew list --formula --versions > "${backup_dir}/manifests/brew-formulae.txt" 2> "${backup_dir}/manifests/brew-formulae.stderr" || true
  brew list --cask --versions > "${backup_dir}/manifests/brew-casks.txt" 2> "${backup_dir}/manifests/brew-casks.stderr" || true
  brew services list > "${backup_dir}/manifests/brew-services.txt" 2> "${backup_dir}/manifests/brew-services.stderr" || true
fi

if command -v nix >/dev/null 2>&1; then
  nix --version > "${backup_dir}/manifests/nix-version.txt" 2>&1 || true
fi

git -C "${repo_root}" status --short > "${backup_dir}/manifests/nix-repo-status.txt" 2>&1 || true
git -C "${repo_root}" rev-parse HEAD > "${backup_dir}/manifests/nix-repo-head.txt" 2>&1 || true

find /Applications -maxdepth 1 -type d -name "*.app" | sort > "${backup_dir}/manifests/applications-system.txt"
find "${HOME}/Applications" -maxdepth 1 -type d -name "*.app" | sort > "${backup_dir}/manifests/applications-user.txt" 2>/dev/null || true

{
  printf '%s\n' "${HOME}/.claude"
  printf '%s\n' "${HOME}/.codex"
  printf '%s\n' "${HOME}/Library/Application Support/Claude"
  printf '%s\n' "${HOME}/Library/Application Support/Code"
  printf '%s\n' "${HOME}/Library/Application Support/Cursor"
  printf '%s\n' "${HOME}/Library/Application Support/Zed"
} > "${backup_dir}/manifests/excluded-paths.txt"

home_paths=(
  ".config"
  ".ssh"
  ".gnupg"
  ".aws"
  ".npmrc"
  ".gitconfig"
  ".gitignore"
  ".zshenv"
  ".zprofile"
  ".zshrc"
  ".zlogin"
  ".zlogout"
  ".bash_profile"
  ".profile"
  ".secrets"
  ".claude.json"
  ".claude.json.backup"
  "dots"
)

library_paths=(
  "Library/Preferences"
  "Library/Fonts"
  "Library/Application Support/Codex"
)

archive_from_home() {
  local archive_name="$1"
  shift
  local source_root="$1"
  shift
  local -a requested=("$@")
  local -a existing=()

  for path in "${requested[@]}"; do
    if [[ -e "${source_root}/${path}" || -L "${source_root}/${path}" ]]; then
      existing+=("${path}")
    fi
  done

  printf '%s\n' "${existing[@]}" > "${backup_dir}/manifests/${archive_name%.tar.gz}-contents.txt"

  if ((${#existing[@]} == 0)); then
    return
  fi

  COPYFILE_DISABLE=1 tar \
    --exclude ".ssh/agent" \
    --exclude ".ssh/controlmasters" \
    -C "${source_root}" \
    -czf "${backup_dir}/archives/${archive_name}" \
    "${existing[@]}"
}

archive_from_home "home-config.tar.gz" "${HOME}" "${home_paths[@]}"
archive_from_home "library-config.tar.gz" "${HOME}" "${library_paths[@]}"

(
  cd "${backup_dir}"
  shasum -a 256 archives/*.tar.gz > manifests/archive-checksums.txt
)

printf 'Backup written to %s\n' "${backup_dir}"
