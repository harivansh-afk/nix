#!/usr/bin/env bash
# Idempotent reconciliation of forgejo mirror state. Repos are discovered at
# runtime from /var/lib/forgejo/data/forgejo.db so this script and its
# committed config carry zero repo inventory. The only operator config lives in
# /etc/forgejo-mirror/manifest.json:
#
#   owned_owner            : the user whose repos get push-mirrored
#   actions_enabled_repos  : the only repos allowed to dispatch CI jobs
#   push_mirror_interval   : forgejo push-mirror periodic interval
#   pull_mirror_interval   : (informational; the prestart script enforces it)
#
# What this does (in order):
#   1. For every repo under `owned_owner`:
#        - If a pull-mirror exists, capture its remote_address and DELETE the
#          row (forgejo can't be both directions cleanly).
#        - If no push-mirror exists yet, create one targeting the captured
#          github URL (or repository.original_url as a fallback). use_ssh=true,
#          sync_on_commit=true. Register the returned public_key as a github
#          deploy key with read_only=false.
#        - Existing push-mirrors are left alone.
#   2. Every repo: flip `has_actions` to match the allowlist.
#   3. Re-jitter the pull-mirror schedule (matches the forgejo prestart hook).
#
# To stop mirroring a specific repo: delete it on forgejo (tea api -X DELETE
# /repos/owner/name). This script doesn't try to be a destructive force.
#
# Safe to re-run. --dry-run prints intended mutations only.

set -euo pipefail

MANIFEST="${FORGEJO_MIRROR_MANIFEST:-/etc/forgejo-mirror/manifest.json}"
DB=/var/lib/forgejo/data/forgejo.db
TEA_LOGIN="${TEA_LOGIN:-harivan}"
DRY=0

for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown arg: $a" >&2; exit 2 ;;
  esac
done

log()  { printf '%s %s\n' "[$(date +%H:%M:%S)]" "$*"; }
warn() { printf '%s WARN  %s\n' "[$(date +%H:%M:%S)]" "$*" >&2; }
die()  { printf '%s FATAL %s\n' "[$(date +%H:%M:%S)]" "$*" >&2; exit 1; }

tea_api() { tea api --login "$TEA_LOGIN" "$@"; }
gh_api()  { gh api "$@"; }

sq() { sqlite3 -bail -batch "$DB" "PRAGMA busy_timeout=10000; $*"; }

# Normalize an SSH URL to the form forgejo stores: ssh://github.com/...
# Strips a leading `git@` user. Leaves https:// untouched.
normalize_ssh() {
  local u="$1"
  case "$u" in
    ssh://git@*) printf 'ssh://%s' "${u#ssh://git@}" ;;
    *)           printf '%s' "$u" ;;
  esac
}

# Convert an https://github.com/owner/repo(.git)? URL to ssh form.
https_to_ssh() {
  local u="$1"
  case "$u" in
    https://github.com/*)
      local rest=${u#https://github.com/}
      rest=${rest%.git}
      printf 'ssh://github.com/%s.git' "$rest"
      ;;
    *) printf '%s' "$u" ;;
  esac
}

require() {
  command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"
}

main() {
  require jq
  require tea
  require gh
  require sqlite3

  [ -r "$MANIFEST" ] || die "manifest not readable: $MANIFEST"
  [ -r "$DB" ]       || die "forgejo db not readable: $DB (need root)"

  log "manifest: $MANIFEST"
  log "db:       $DB"
  [ "$DRY" = "1" ] && log "DRY RUN (no mutations will be applied)"

  local owned_owner sync_on_commit interval
  owned_owner=$(jq -r '.owned_owner' "$MANIFEST")
  sync_on_commit=$(jq -r '.push_mirror_sync_on_commit' "$MANIFEST")
  interval=$(jq -r '.push_mirror_interval' "$MANIFEST")

  local actions_enabled
  actions_enabled=$(jq -r '.actions_enabled_repos[]' "$MANIFEST")

  # ------------------------------------------------------------------------
  # 1. Owned repos: convert pull -> push, ensure push-mirror exists
  # ------------------------------------------------------------------------
  log "phase 1: ensuring push-mirrors for $owned_owner/*"

  while IFS=$'\t' read -r rid name original_url; do
    [ -z "$rid" ] && continue
    local path="$owned_owner/$name"

    local pull_url
    pull_url=$(sq "SELECT remote_address FROM mirror WHERE repo_id=$rid LIMIT 1;" || true)
    if [ -n "$pull_url" ]; then
      log "  $path: deleting inbound pull-mirror (was: $pull_url)"
      [ "$DRY" = "1" ] || sq "DELETE FROM mirror WHERE repo_id=$rid; UPDATE repository SET is_mirror=0 WHERE id=$rid;"
    fi

    local target=""
    if [ -n "$pull_url" ]; then
      target=$(normalize_ssh "$(https_to_ssh "$pull_url")")
    fi
    if [ -z "$target" ] && [ -n "$original_url" ]; then
      target=$(normalize_ssh "$(https_to_ssh "$original_url")")
    fi
    if [ -z "$target" ]; then
      target=$(sq "SELECT remote_address FROM push_mirror WHERE repo_id=$rid LIMIT 1;" || true)
    fi
    if [ -z "$target" ]; then
      warn "  $path: no upstream URL known (no pull-mirror, no original_url, no push-mirror); skipping"
      continue
    fi

    local existing
    existing=$(tea_api "/repos/$owned_owner/$name/push_mirrors" 2>/dev/null \
      | jq -r --arg t "$target" '.[] | select(.remote_address==$t) | .remote_name' \
      || true)
    if [ -n "$existing" ]; then
      log "  $path -> $target: push-mirror present"
      continue
    fi

    log "  $path -> $target: creating push-mirror"
    if [ "$DRY" = "1" ]; then
      continue
    fi

    local body resp pubkey
    body=$(jq -nc \
      --arg addr "$target" \
      --arg interval "$interval" \
      --argjson sync "$sync_on_commit" \
      '{remote_address:$addr, use_ssh:true, sync_on_commit:$sync, interval:$interval}')
    resp=$(printf '%s' "$body" | tea_api -X POST "/repos/$owned_owner/$name/push_mirrors" -H "Content-Type: application/json" --input -) \
      || { warn "  $path: tea api failed; skipping"; continue; }
    pubkey=$(printf '%s' "$resp" | jq -r '.public_key // empty')
    if [ -z "$pubkey" ]; then
      warn "  $path: forgejo returned no public_key; cannot install deploy key"
      continue
    fi

    log "  $path: registering deploy key on github"
    gh_api -X POST "/repos/$owned_owner/$name/keys" \
      -F "title=forgejo push-mirror (spark)" \
      -F "key=$pubkey" \
      -F "read_only=false" >/dev/null \
      || warn "  $path: gh deploy-key registration failed"

    log "  $path: triggering initial sync"
    tea_api -X POST "/repos/$owned_owner/$name/push_mirrors-sync" >/dev/null \
      || warn "  $path: sync trigger failed"
  done < <(sq "SELECT r.id, r.lower_name, COALESCE(r.original_url,'') FROM repository r JOIN user u ON u.id=r.owner_id WHERE u.lower_name='$owned_owner' AND r.is_empty=0 ORDER BY r.lower_name;" -separator $'\t')

  # ------------------------------------------------------------------------
  # 2. actions: enable only on allowlist
  # ------------------------------------------------------------------------
  log "phase 2: gating forgejo Actions per allowlist"
  declare -A allow
  while IFS= read -r p; do allow["$p"]=1; done <<< "$actions_enabled"

  while IFS=$'\t' read -r owner name; do
    [ -z "$owner" ] && continue
    local path="$owner/$name"
    local want=0
    [ -n "${allow[$path]+x}" ] && want=1

    local cur
    cur=$(tea_api "/repos/$owner/$name" 2>/dev/null | jq -r '.has_actions // false') || true
    if [ "$want" = "1" ] && [ "$cur" = "true" ]; then continue; fi
    if [ "$want" = "0" ] && [ "$cur" = "false" ]; then continue; fi

    local target_bool
    [ "$want" = "1" ] && target_bool=true || target_bool=false
    log "  $path: has_actions $cur -> $target_bool"
    [ "$DRY" = "1" ] && continue
    printf '{"has_actions": %s}' "$target_bool" \
      | tea_api -X PATCH "/repos/$owner/$name" -H "Content-Type: application/json" --input - >/dev/null \
      || warn "  $path: tea api patch failed"
  done < <(sq "SELECT u.lower_name, r.lower_name FROM repository r JOIN user u ON u.id=r.owner_id WHERE r.is_archived=0 AND r.is_empty=0 ORDER BY u.lower_name, r.lower_name;" -separator $'\t')

  # ------------------------------------------------------------------------
  # 3. re-jitter pull-mirror schedule (matches the forgejo prestart hook)
  # ------------------------------------------------------------------------
  log "phase 3: re-jittering pull-mirror schedule"
  local interval_seconds=$((15 * 60))
  local interval_nanos=$((interval_seconds * 1000000000))
  if [ "$DRY" = "1" ]; then
    log "  DRY would update mirror table with interval=15m and uniform jitter"
  else
    sq "UPDATE mirror SET interval=$interval_nanos, next_update_unix=CAST(strftime('%s','now') AS INTEGER) + (repo_id % $interval_seconds);"
  fi

  log "done"
}

main "$@"
