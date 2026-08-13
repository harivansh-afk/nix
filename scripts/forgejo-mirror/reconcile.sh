set -euo pipefail

MANIFEST="${FORGEJO_MIRROR_MANIFEST:-/etc/forgejo-mirror/manifest.json}"
DB=/var/lib/forgejo/data/forgejo.db
TEA_LOGIN="${TEA_LOGIN:-harivan}"
DRY=0

for a in "$@"; do
  case "$a" in
  --dry-run) DRY=1 ;;
  -h | --help)
    sed -n '2,30p' "$0"
    exit 0
    ;;
  *)
    echo "unknown arg: $a" >&2
    exit 2
    ;;
  esac
done

log() { printf '%s %s\n' "[$(date +%H:%M:%S)]" "$*"; }
warn() { printf '%s WARN  %s\n' "[$(date +%H:%M:%S)]" "$*" >&2; }
die() {
  printf '%s FATAL %s\n' "[$(date +%H:%M:%S)]" "$*" >&2
  exit 1
}

tea_api() { tea api --login "$TEA_LOGIN" "$@"; }
gh_api() { gh api "$@"; }

# Tab-separated, quiet 10s lock timeout. Options must precede the db path;
# a leading PRAGMA would echo its value into the results, so use .timeout.
sq() { sqlite3 -bail -batch -cmd '.timeout 10000' -cmd '.mode tabs' "$DB" "$*"; }

# Normalize an SSH URL to the form forgejo stores: ssh://github.com/...
# Strips a leading `git@` user. Leaves https:// untouched.
normalize_ssh() {
  local u="$1"
  case "$u" in
  ssh://git@*) printf 'ssh://%s' "${u#ssh://git@}" ;;
  *) printf '%s' "$u" ;;
  esac
}

# Convert an https://github.com/owner/repo(.git)? URL to ssh form.
# Also strips embedded userinfo (https://TOKEN@github.com/...).
https_to_ssh() {
  local u="$1"
  case "$u" in
  https://github.com/* | https://*@github.com/*)
    local rest=${u#https://}
    rest=${rest#*@}
    rest=${rest#github.com/}
    rest=${rest%.git}
    printf 'ssh://github.com/%s.git' "$rest"
    ;;
  *) printf '%s' "$u" ;;
  esac
}

# Strip embedded userinfo from an https github URL, leave anything else as-is.
# Mirror auth belongs in the git credential store (fed from sops by the
# forgejo preStart), never embedded in remote URLs.
strip_cred() {
  local u="$1"
  case "$u" in
  https://*@github.com/*) printf 'https://github.com/%s' "${u#https://*@github.com/}" ;;
  *) printf '%s' "$u" ;;
  esac
}

# Probe a remote the way forgejo syncs: as the git user, with its HOME and
# thus its credential store. -C / because the caller's cwd (e.g. a checkout
# under /home) may not be readable by the git user.
probe_as_git() {
  runuser -u git -- env HOME=/var/lib/forgejo GIT_TERMINAL_PROMPT=0 \
    git -C / ls-remote "$1" HEAD >/dev/null 2>&1
}

# Print the upstream HEAD commit id (empty if unreachable).
remote_head_as_git() {
  runuser -u git -- env HOME=/var/lib/forgejo GIT_TERMINAL_PROMPT=0 \
    git -C / ls-remote "$1" HEAD 2>/dev/null | awk '{print $1; exit}'
}

require() {
  command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"
}

main() {
  require jq
  require tea
  require gh
  require sqlite3
  require git
  require runuser

  [ -r "$MANIFEST" ] || die "manifest not readable: $MANIFEST"
  [ -r "$DB" ] || die "forgejo db not readable: $DB (need root)"

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
    local dir="/var/lib/forgejo/repositories/$owned_owner/$name.git"

    # The pull-mirror fetch URL lives in the bare repo's git config (the DB
    # only holds an encrypted copy for the UI). No mutation yet: converting
    # is only safe once the guards below pass.
    local pull_url="" is_pull=""
    is_pull=$(sq "SELECT 1 FROM mirror WHERE repo_id=$rid LIMIT 1;" || true)
    if [ -n "$is_pull" ]; then
      pull_url=$(runuser -u git -- git -C "$dir" remote get-url origin 2>/dev/null || true)
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
      # Native forgejo repo (never lived on github): default to the canonical
      # github address; the repo is created below if it does not exist yet.
      target="ssh://github.com/$owned_owner/$name.git"
      log "  $path: no upstream URL known; defaulting to $target"
    fi

    local existing
    existing=$(tea_api "/repos/$owned_owner/$name/push_mirrors" 2>/dev/null |
      jq -r --arg t "$target" '.[] | select(.remote_address==$t) | .remote_name' ||
      true)
    if [ -n "$existing" ]; then
      log "  $path -> $target: push-mirror present"
      continue
    fi

    # Guard: never let two repos push-mirror the same github target (they
    # would take turns force-pushing over each other).
    local other
    other=$(sq "SELECT repo_id FROM push_mirror WHERE remote_address='$target' AND repo_id<>$rid LIMIT 1;" || true)
    if [ -n "$other" ]; then
      warn "  $path: $target is already push-mirrored by repo id $other; leaving untouched"
      continue
    fi

    # Guard: converting a live pull-mirror flips the direction of truth. Only
    # do it when local and upstream HEAD agree, so nothing can be clobbered.
    if [ -n "$is_pull" ] && [ -n "$pull_url" ]; then
      local local_head remote_head
      local_head=$(runuser -u git -- git -C "$dir" rev-parse HEAD 2>/dev/null || true)
      remote_head=$(remote_head_as_git "$(strip_cred "$pull_url")")
      if [ -n "$local_head" ] && [ -n "$remote_head" ] && [ "$local_head" != "$remote_head" ]; then
        warn "  $path: local HEAD ${local_head:0:10} != upstream ${remote_head:0:10}; not converting"
        continue
      fi
    fi

    log "  $path -> $target: creating push-mirror"
    if [ "$DRY" = "1" ]; then
      continue
    fi

    if [ -n "$is_pull" ]; then
      log "  $path: deleting inbound pull-mirror (was: ${pull_url:-unknown})"
      sq "DELETE FROM mirror WHERE repo_id=$rid; UPDATE repository SET is_mirror=0 WHERE id=$rid;"
    fi

    # Ensure the github repo exists (native repos have no github counterpart).
    local gh_path
    gh_path=${target#ssh://github.com/}
    gh_path=${gh_path%.git}
    if ! gh_api "/repos/$gh_path" >/dev/null 2>&1; then
      local is_private vis_flag
      is_private=$(sq "SELECT is_private FROM repository WHERE id=$rid;")
      vis_flag=--public
      [ "$is_private" = "1" ] && vis_flag=--private
      log "  $path: creating github repo $gh_path ($vis_flag)"
      gh repo create "$gh_path" "$vis_flag" >/dev/null ||
        {
          warn "  $path: gh repo create failed; skipping"
          continue
        }
    fi

    local body resp pubkey
    body=$(jq -nc \
      --arg addr "$target" \
      --arg interval "$interval" \
      --argjson sync "$sync_on_commit" \
      '{remote_address:$addr, use_ssh:true, sync_on_commit:$sync, interval:$interval}')
    resp=$(printf '%s' "$body" | tea_api -X POST "/repos/$owned_owner/$name/push_mirrors" -d @-) ||
      {
        warn "  $path: tea api failed; skipping"
        continue
      }
    pubkey=$(printf '%s' "$resp" | jq -r '.public_key // empty')
    if [ -z "$pubkey" ]; then
      warn "  $path: forgejo returned no public_key; cannot install deploy key"
      continue
    fi

    log "  $path: registering deploy key on github"
    gh_api -X POST "/repos/$owned_owner/$name/keys" \
      -F "title=forgejo push-mirror (spark)" \
      -F "key=$pubkey" \
      -F "read_only=false" >/dev/null ||
      warn "  $path: gh deploy-key registration failed"

    log "  $path: triggering initial sync"
    tea_api -X POST "/repos/$owned_owner/$name/push_mirrors-sync" >/dev/null ||
      warn "  $path: sync trigger failed"
  done < <(sq "SELECT r.id, r.lower_name, COALESCE(r.original_url,'') FROM repository r JOIN user u ON u.id=r.owner_id WHERE u.lower_name='$owned_owner' AND r.is_empty=0 AND r.is_archived=0 ORDER BY r.lower_name;")

  # ------------------------------------------------------------------------
  # 1b. Non-owned pull mirrors: strip embedded credentials from remote URLs
  #     (auth belongs to the credential store fed by forgejo's preStart), and
  #     convert mirrors whose upstream is gone into regular repos (data kept).
  # ------------------------------------------------------------------------
  log "phase 1b: repairing non-owned pull mirrors"

  # Abort the phase if github itself is unreachable, so a network blip can
  # never mass-convert mirrors to regular repos.
  if ! probe_as_git https://github.com/git/git.git; then
    warn "  github unreachable from the git user; skipping phase 1b"
  else
    while IFS=$'\t' read -r rid owner name; do
      [ -z "$rid" ] && continue
      local path="$owner/$name"
      local dir="/var/lib/forgejo/repositories/$owner/$name.git"

      local url clean
      url=$(runuser -u git -- git -C "$dir" remote get-url origin 2>/dev/null || true)
      if [ -z "$url" ]; then
        warn "  $path: no origin remote; skipping"
        continue
      fi
      clean=$(strip_cred "$url")

      if probe_as_git "$clean"; then
        if [ "$clean" != "$url" ]; then
          # The DB only holds an encrypted display copy of the address; the
          # URL git actually fetches from is the bare repo's git config.
          log "  $path: stripping embedded credential from remote URL"
          [ "$DRY" = "1" ] || runuser -u git -- git -C "$dir" remote set-url origin "$clean"
        fi
      else
        log "  $path: upstream unreachable ($clean); converting to regular repo (data kept)"
        if [ "$DRY" != "1" ]; then
          sq "DELETE FROM mirror WHERE repo_id=$rid; UPDATE repository SET is_mirror=0 WHERE id=$rid;"
          [ "$clean" = "$url" ] || runuser -u git -- git -C "$dir" remote set-url origin "$clean"
        fi
      fi
    done < <(sq "SELECT r.id, u.lower_name, r.lower_name FROM repository r JOIN user u ON u.id=r.owner_id JOIN mirror m ON m.repo_id=r.id WHERE u.lower_name != '$owned_owner' ORDER BY u.lower_name, r.lower_name;")
  fi

  # ------------------------------------------------------------------------
  # 2. actions: enable only on allowlist
  # ------------------------------------------------------------------------
  log "phase 2: gating forgejo Actions per allowlist"
  declare -A allow
  while IFS= read -r p; do allow["$p"]=1; done <<<"$actions_enabled"

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
    printf '{"has_actions": %s}' "$target_bool" |
      tea_api -X PATCH "/repos/$owner/$name" -H "Content-Type: application/json" --input - >/dev/null ||
      warn "  $path: tea api patch failed"
  done < <(sq "SELECT u.lower_name, r.lower_name FROM repository r JOIN user u ON u.id=r.owner_id WHERE r.is_archived=0 AND r.is_empty=0 ORDER BY u.lower_name, r.lower_name;")

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
