#!/usr/bin/env bash
set -euo pipefail

forgejo_url="${FORGEJO_URL:-https://git.harivan.sh}"
forgejo_db="${FORGEJO_DB:-/var/lib/forgejo/data/forgejo.db}"
github_api="${GITHUB_API:-https://api.github.com}"
apply=false
only_owner=""

usage() {
  printf 'usage: %s [--apply] [--only owner]\n' "$0" >&2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
  --apply)
    apply=true
    shift
    ;;
  --only)
    [ "$#" -ge 2 ] || {
      usage
      exit 2
    }
    only_owner="$2"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    usage
    exit 2
    ;;
  esac
done

if [ -z "${FORGEJO_TOKEN:-}" ] && [ -r /run/secrets/forgejo-mirror.env ]; then
  set -a
  # shellcheck source=/dev/null
  . /run/secrets/forgejo-mirror.env
  set +a
fi

if [ "$apply" = true ] && [ -z "${FORGEJO_TOKEN:-}" ]; then
  echo "FORGEJO_TOKEN is required with --apply" >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

sqlite_query="$(
  cat <<'SQL'
SELECT u.name, u.type, r.original_url
FROM repository r
JOIN user u ON u.id = r.owner_id
WHERE r.is_mirror = 1
  AND r.original_url LIKE '%github.com%';
SQL
)"

github_owner_from_url() {
  case "$1" in
  https://github.com/*/* | http://github.com/*/*)
    local rest="${1#*://github.com/}"
    printf '%s\n' "${rest%%/*}"
    ;;
  git@github.com:*/*)
    local rest="${1#git@github.com:}"
    printf '%s\n' "${rest%%/*}"
    ;;
  ssh://git@github.com/*/*)
    local rest="${1#ssh://git@github.com/}"
    printf '%s\n' "${rest%%/*}"
    ;;
  *)
    return 1
    ;;
  esac
}

github_get() {
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -fsS \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      "$@"
  else
    curl -fsS \
      -H "Accept: application/vnd.github+json" \
      "$@"
  fi
}

declare -A owner_types
declare -A github_owners
declare -A github_owner_counts
declare -A mirror_counts

while IFS=$'\t' read -r owner owner_type original_url; do
  [ -n "$owner" ] || continue
  github_owner="$(github_owner_from_url "$original_url" || true)"
  [ -n "$github_owner" ] || continue

  owner_types["$owner"]="$owner_type"
  mirror_counts["$owner"]="$((${mirror_counts["$owner"]:-0} + 1))"

  key="$owner"$'\t'"$github_owner"
  if [ -z "${github_owner_counts["$key"]+set}" ]; then
    github_owners["$owner"]="${github_owners["$owner"]:-}$github_owner"$'\n'
    github_owner_counts["$key"]=1
  else
    github_owner_counts["$key"]="$((${github_owner_counts["$key"]} + 1))"
  fi
done < <(sqlite3 -batch -separator $'\t' "$forgejo_db" "$sqlite_query")

for owner in "${!owner_types[@]}"; do
  if [ -n "$only_owner" ] && [ "$owner" != "$only_owner" ]; then
    continue
  fi

  owner_type="${owner_types["$owner"]}"
  if [ "$owner_type" != "1" ]; then
    printf 'skip user %-24s mirrors=%s reason=not-org\n' "$owner" "${mirror_counts["$owner"]}"
    continue
  fi

  unique_count="$(printf '%s' "${github_owners["$owner"]}" | sed '/^$/d' | sort -u | wc -l | tr -d ' ')"
  if [ "$unique_count" != "1" ]; then
    printf 'skip org  %-24s mirrors=%s reason=ambiguous-github-owner owners=%s\n' \
      "$owner" "${mirror_counts["$owner"]}" "$(printf '%s' "${github_owners["$owner"]}" | sed '/^$/d' | sort -u | paste -sd, -)"
    continue
  fi

  github_owner="$(printf '%s' "${github_owners["$owner"]}" | sed '/^$/d' | sort -u)"
  github_json="$tmpdir/github-$owner.json"
  if ! github_get "$github_api/users/$github_owner" >"$github_json"; then
    printf 'skip org  %-24s github=%-24s reason=github-fetch-failed\n' "$owner" "$github_owner"
    continue
  fi

  avatar_url="$(jq -r '.avatar_url // empty' "$github_json")"
  if [ -z "$avatar_url" ]; then
    printf 'skip org  %-24s github=%-24s reason=no-avatar-url\n' "$owner" "$github_owner"
    continue
  fi

  printf '%s org  %-24s github=%-24s mirrors=%s avatar=%s\n' \
    "$([ "$apply" = true ] && printf apply || printf dry-run)" \
    "$owner" "$github_owner" "${mirror_counts["$owner"]}" "$avatar_url"

  if [ "$apply" != true ]; then
    continue
  fi

  image_file="$tmpdir/$owner.avatar"
  github_get "$avatar_url" >"$image_file"
  image_b64="$(base64 -w0 "$image_file")"
  payload="$tmpdir/$owner.payload.json"
  jq -n --arg image "$image_b64" '{image: $image}' >"$payload"

  curl -fsS \
    -X POST \
    -H "Authorization: token $FORGEJO_TOKEN" \
    -H "Content-Type: application/json" \
    --data-binary "@$payload" \
    "$forgejo_url/api/v1/orgs/$owner/avatar" >/dev/null
done
