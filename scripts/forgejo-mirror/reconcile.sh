#!/usr/bin/env bash
# Idempotent reconciliation of forgejo mirror state against the declarative
# manifest at /etc/forgejo-mirror/manifest.json.
#
# What this does (in order):
#   1. For every repo listed in `no_mirror`: delete its pull-mirror row,
#      delete its push-mirror rows, and clear `is_mirror=0` on the repo.
#   2. For every repo in `push_mirrors`: if a pull-mirror exists, delete it
#      (Forgejo cannot run both directions cleanly), then ensure a push-mirror
#      exists with `use_ssh=true sync_on_commit=true interval=15m`. New
#      push-mirrors get a fresh ed25519 deploy key registered on GitHub via
#      gh api. Existing push-mirrors are left alone.
#   3. For every repo: set `has_actions` true iff the repo path is in
#      `actions_enabled_repos`, false otherwise.
#   4. Normalize the pull-mirror schedule one more time (uniform jitter across
#      the 15m cycle) so reconciliation lands in the same scheduling space the
#      forgejo prestart script uses.
#
# Requirements:
#   - run as root on spark (needs to read /var/lib/forgejo/data/forgejo.db
#     and edit it via sqlite3)
#   - tea CLI logged into `git.harivan.sh` as harivansh-afk
#   - gh CLI logged in with `admin:public_key` + `repo` scopes
#
# Safe to re-run. Logs every action; pass --dry-run to skip mutations.

set -euo pipefail

MANIFEST="${FORGEJO_MIRROR_MANIFEST:-/etc/forgejo-mirror/manifest.json}"
DB=/var/lib/forgejo/data/forgejo.db
TEA_LOGIN="${TEA_LOGIN:-harivan}"
DRY=0

for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    -h|--help)
      sed -n '2,30p' "$0"
      exit 0
      ;;
    *) echo "unknown arg: $a" >&2; exit 2 ;;
  esac
done

log()  { printf '%s %s\n' "[$(date +%H:%M:%S)]" "$*"; }
warn() { printf '%s WARN  %s\n' "[$(date +%H:%M:%S)]" "$*" >&2; }
die()  { printf '%s FATAL %s\n' "[$(date +%H:%M:%S)]" "$*" >&2; exit 1; }

run() {
  if [ "$DRY" = "1" ]; then
    printf '  DRY %s\n' "$*"
  else
    "$@"
  fi
}

# tea helpers. tea passes URL-encoded args through to the forgejo REST API.
# We call tea api directly because the `tea repos`/`tea push-mirrors`
# subcommands don't cover the full surface we need.
tea_api() {
  tea api --login "$TEA_LOGIN" "$@"
}

gh_api() {
  gh api "$@"
}

# sqlite3 helper that talks to forgejo's DB with WAL + a generous busy
# timeout so we don't fight forgejo for the lock.
sq() {
  sqlite3 -bail -batch "$DB" "PRAGMA busy_timeout=10000; $*"
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

  local no_mirror push_mirrors actions_enabled
  no_mirror=$(jq -r '.no_mirror[]' "$MANIFEST")
  push_mirrors=$(jq -r '.push_mirrors | keys[]' "$MANIFEST")
  actions_enabled=$(jq -r '.actions_enabled_repos[]' "$MANIFEST")

  # --------------------------------------------------------------------------
  # 1. no_mirror: tear down every mirror row for these repos
  # --------------------------------------------------------------------------
  log "phase 1: clearing mirrors on no_mirror set"
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    local owner name
    owner="${path%%/*}"; name="${path##*/}"
    local rid
    rid=$(sq "SELECT r.id FROM repository r JOIN user u ON u.id=r.owner_id WHERE u.lower_name='$owner' AND r.lower_name='$name';" || true)
    [ -z "$rid" ] && { warn "no_mirror: repo $path not found, skipping"; continue; }

    local pull_count push_count
    pull_count=$(sq "SELECT COUNT(*) FROM mirror WHERE repo_id=$rid;")
    push_count=$(sq "SELECT COUNT(*) FROM push_mirror WHERE repo_id=$rid;")
    if [ "$pull_count" = "0" ] && [ "$push_count" = "0" ]; then
      log "  $path already mirror-free"
      continue
    fi
    log "  $path: deleting $pull_count pull + $push_count push mirror rows"
    run sq "DELETE FROM mirror WHERE repo_id=$rid; DELETE FROM push_mirror WHERE repo_id=$rid; UPDATE repository SET is_mirror=0 WHERE id=$rid;"
  done <<< "$no_mirror"

  # --------------------------------------------------------------------------
  # 2. push_mirrors: convert any pull-mirror to push, ensure push-mirror exists
  # --------------------------------------------------------------------------
  log "phase 2: ensuring push-mirrors"
  local sync_on_commit interval
  sync_on_commit=$(jq -r '.push_mirror_sync_on_commit' "$MANIFEST")
  interval=$(jq -r '.push_mirror_interval' "$MANIFEST")

  while IFS= read -r path; do
    [ -z "$path" ] && continue
    local owner name target rid
    owner="${path%%/*}"; name="${path##*/}"
    target=$(jq -r --arg p "$path" '.push_mirrors[$p]' "$MANIFEST")
    rid=$(sq "SELECT r.id FROM repository r JOIN user u ON u.id=r.owner_id WHERE u.lower_name='$owner' AND r.lower_name='$name';" || true)
    [ -z "$rid" ] && { warn "push: repo $path not found, skipping"; continue; }

    # 2a. drop any inbound pull-mirror; forgejo can't be both.
    local pull_count
    pull_count=$(sq "SELECT COUNT(*) FROM mirror WHERE repo_id=$rid;")
    if [ "$pull_count" != "0" ]; then
      log "  $path: deleting $pull_count inbound pull-mirror row(s); flipping is_mirror=0"
      run sq "DELETE FROM mirror WHERE repo_id=$rid; UPDATE repository SET is_mirror=0 WHERE id=$rid;"
    fi

    # 2b. ensure outbound push-mirror to the configured target.
    local existing
    existing=$(tea_api "/repos/$owner/$name/push_mirrors" 2>/dev/null \
      | jq -r --arg t "$target" '.[] | select(.remote_address==$t) | .remote_name' \
      || true)
    if [ -n "$existing" ]; then
      log "  $path -> $target: push-mirror present ($existing), leaving alone"
      continue
    fi

    log "  $path -> $target: creating push-mirror"
    local body resp pubkey
    body=$(jq -nc \
      --arg addr "$target" \
      --arg interval "$interval" \
      --argjson sync "$sync_on_commit" \
      '{remote_address:$addr, use_ssh:true, sync_on_commit:$sync, interval:$interval}')
    if [ "$DRY" = "1" ]; then
      printf '  DRY tea_api POST /repos/%s/%s/push_mirrors  body=%s\n' "$owner" "$name" "$body"
      continue
    fi
    resp=$(printf '%s' "$body" | tea_api -X POST "/repos/$owner/$name/push_mirrors" -H "Content-Type: application/json" --input -) \
      || { warn "  $path: tea api failed; skipping"; continue; }
    pubkey=$(printf '%s' "$resp" | jq -r '.public_key // empty')
    if [ -z "$pubkey" ]; then
      warn "  $path: forgejo did not return a public_key; cannot install deploy key"
      continue
    fi

    log "  $path: registering deploy key on github"
    gh_api -X POST "/repos/$owner/$name/keys" \
      -F "title=forgejo push-mirror (spark)" \
      -F "key=$pubkey" \
      -F "read_only=false" >/dev/null \
      || warn "  $path: gh api deploy-key creation failed; mirror exists but will not push until key is added"

    log "  $path: triggering initial sync"
    tea_api -X POST "/repos/$owner/$name/push_mirrors-sync" >/dev/null \
      || warn "  $path: initial sync trigger failed"
  done <<< "$push_mirrors"

  # --------------------------------------------------------------------------
  # 3. actions: enable only on allowlist, disable everywhere else
  # --------------------------------------------------------------------------
  log "phase 3: gating forgejo Actions per allowlist"
  # Build a hash lookup of repos with actions enabled.
  declare -A allow
  while IFS= read -r p; do allow["$p"]=1; done <<< "$actions_enabled"

  # Iterate every repo via SQL (tea api /repos/search caps at 50/page and we
  # have ~200 repos). is_archived/is_empty repos are skipped to avoid noise.
  while IFS=$'\t' read -r owner name; do
    [ -z "$owner" ] && continue
    local path="$owner/$name"
    local want_enabled=0
    if [ -n "${allow[$path]+x}" ]; then
      want_enabled=1
    fi

    # Current state: tea returns has_actions in the repo object.
    local cur
    cur=$(tea_api "/repos/$owner/$name" 2>/dev/null | jq -r '.has_actions // false') || true
    if [ "$want_enabled" = "1" ] && [ "$cur" = "true" ]; then
      continue
    fi
    if [ "$want_enabled" = "0" ] && [ "$cur" = "false" ]; then
      continue
    fi

    local target_bool
    [ "$want_enabled" = "1" ] && target_bool=true || target_bool=false
    log "  $path: has_actions $cur -> $target_bool"
    if [ "$DRY" = "1" ]; then
      continue
    fi
    printf '{"has_actions": %s}' "$target_bool" \
      | tea_api -X PATCH "/repos/$owner/$name" -H "Content-Type: application/json" --input - >/dev/null \
      || warn "  $path: tea api patch failed"
  done < <(sq "SELECT u.lower_name, r.lower_name FROM repository r JOIN user u ON u.id=r.owner_id WHERE r.is_archived=0 AND r.is_empty=0 ORDER BY u.lower_name, r.lower_name;" -separator $'\t')

  # --------------------------------------------------------------------------
  # 4. re-normalize pull-mirror schedule (uniform jitter, 15m cycle)
  # --------------------------------------------------------------------------
  log "phase 4: re-jittering pull-mirror schedule"
  local interval_seconds interval_nanos
  interval_seconds=$((15 * 60))
  interval_nanos=$((interval_seconds * 1000000000))
  if [ "$DRY" = "1" ]; then
    log "  DRY: would update mirror table with interval=$interval_seconds and uniform jitter"
  else
    sq "UPDATE mirror SET interval=$interval_nanos, next_update_unix=CAST(strftime('%s','now') AS INTEGER) + (repo_id % $interval_seconds);"
  fi

  log "done"
}

main "$@"
