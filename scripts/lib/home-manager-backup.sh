#!/usr/bin/env bash
set -euo pipefail

if [[ $# -eq 0 ]]; then
  exit 0
fi

target_path="${1:?expected target path}"
base_backup="${target_path}.hm-bak"

if [[ ! -e "$base_backup" ]]; then
  mv "$target_path" "$base_backup"
  exit 0
fi

timestamp="$(date +%Y%m%d-%H%M%S)"
backup_path="${base_backup}.${timestamp}"
suffix=0

while [[ -e "$backup_path" ]]; do
  suffix=$((suffix + 1))
  backup_path="${base_backup}.${timestamp}.${suffix}"
done

mv "$target_path" "$backup_path"
