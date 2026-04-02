#!/usr/bin/env bash
set -euo pipefail
export NODE_NO_WARNINGS=1

if ! command -v bw >/dev/null 2>&1; then
  echo "bw is not installed" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is not installed" >&2
  exit 1
fi

if ! command -v agent-browser >/dev/null 2>&1; then
  echo "agent-browser is not installed" >&2
  exit 1
fi

if [[ "${BW_SESSION:-}" == "" ]]; then
  echo 'BW_SESSION is not set. Run: export BW_SESSION="$(bw unlock --raw)"' >&2
  exit 1
fi

bw sync --session "${BW_SESSION}" >/dev/null 2>&1 || true

items_json="$(bw list items --session "${BW_SESSION}")"

# type 1 = login items; filter to those with a username, password, and at least one URI
login_items="$(printf '%s' "${items_json}" | jq -c '
  [.[] | select(
    .type == 1 and
    .login.username != null and
    .login.username != "" and
    .login.password != null and
    .login.password != "" and
    (.login.uris // []) | length > 0
  )]
')"

count="$(printf '%s' "${login_items}" | jq 'length')"
printf 'Found %d login items with credentials and URIs\n' "${count}"

imported=0
skipped=0
failed=0

printf '%s' "${login_items}" | jq -c '.[]' | while IFS= read -r item; do
  name="$(printf '%s' "${item}" | jq -r '.name')"
  username="$(printf '%s' "${item}" | jq -r '.login.username')"
  password="$(printf '%s' "${item}" | jq -r '.login.password')"
  uri="$(printf '%s' "${item}" | jq -r '.login.uris[0].uri')"

  # Sanitize name for use as agent-browser profile name:
  # keep only alphanumeric, hyphens, underscores; collapse runs; truncate
  safe_name="$(printf '%s' "${name}" | tr -cs 'A-Za-z0-9_-' '-' | sed 's/^-//;s/-$//' | head -c 64)"

  if [[ -z "${safe_name}" ]]; then
    printf 'SKIP (empty name after sanitize): %s\n' "${name}"
    skipped=$((skipped + 1))
    continue
  fi

  # Skip items whose URI is not an http(s) URL
  case "${uri}" in
    http://*|https://*)
      ;;
    *)
      printf 'SKIP (non-http URI): %s -> %s\n' "${name}" "${uri}"
      skipped=$((skipped + 1))
      continue
      ;;
  esac

  if printf '%s' "${password}" | agent-browser auth save "${safe_name}" \
       --url "${uri}" \
       --username "${username}" \
       --password-stdin >/dev/null 2>&1; then
    printf 'OK: %s (%s)\n' "${safe_name}" "${uri}"
    imported=$((imported + 1))
  else
    printf 'FAIL: %s (%s)\n' "${safe_name}" "${uri}" >&2
    failed=$((failed + 1))
  fi
done

printf '\nDone. imported=%d skipped=%d failed=%d\n' "${imported}" "${skipped}" "${failed}"
