#!/usr/bin/env bash
set -euo pipefail

docs_dir="${HOME}/Documents/GitHub/claude-code-docs"
manifest="${docs_dir}/docs/docs_manifest.json"
last_pull="${docs_dir}/.last_pull"

file_path="$(jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
case "${file_path}" in
  "${docs_dir}"/*) ;;
  *) exit 0 ;;
esac

if [[ ! -d "${docs_dir}/.git" || ! -f "${manifest}" ]]; then
  exit 0
fi

github_unix="$(
  python3 - "${manifest}" <<'PY'
import datetime
import json
import sys

manifest_path = sys.argv[1]

try:
    with open(manifest_path, encoding="utf-8") as handle:
        last_updated = json.load(handle).get("last_updated", "")
    last_updated = last_updated.split(".", 1)[0]
    parsed = datetime.datetime.strptime(last_updated, "%Y-%m-%dT%H:%M:%S")
    print(int(parsed.replace(tzinfo=datetime.timezone.utc).timestamp()))
except Exception:
    print(0)
PY
)"

last_synced=0
if [[ -f "${last_pull}" ]]; then
  last_synced="$(cat "${last_pull}" 2>/dev/null || echo 0)"
fi

if [[ "${github_unix}" -le "${last_synced}" ]]; then
  exit 0
fi

printf 'Syncing Claude docs to latest version...\n' >&2
git -C "${docs_dir}" pull --quiet
date +%s > "${last_pull}"
