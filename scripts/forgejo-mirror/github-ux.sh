#!/usr/bin/env bash
# Apply the "barrettruth full treatment" to every owned repo that currently
# has a forgejo->github push-mirror. Targets are discovered from forgejo's
# push_mirror table at runtime; nothing is hardcoded. For each repo:
#
#   1. github metadata: description prefix, homepage, has_issues/wiki/projects=false,
#      archived=false (unarchive if v1 deprecation left it archived).
#   2. .github/README.md in forgejo: banner + full root README, propagated to
#      github by the push-mirror.
#   3. .github/workflows/redirect-pr-to-forgejo.yaml in forgejo: closes inbound
#      github PRs with a forgejo redirect.
#
# Items 2 and 3 are committed to forgejo via the API (no local clone), then
# the script triggers `push_mirrors-sync` to fan them out to github.
#
# This script is intentionally NOT auto-run on rebuild. Run it once after the
# initial deploy, then re-run only when you want to refresh metadata.
#
# Requirements:
#   - tea CLI logged into git.harivan.sh as harivansh-afk
#   - gh CLI logged in with `repo` scope (admin:public_key not required here;
#     reconcile.sh handles deploy keys)
#
# Flags:
#   --dry-run             print intended mutations, perform none
#   --skip-metadata       don't touch github description/homepage/has_*
#   --skip-banner         don't commit .github/README.md
#   --skip-redirect       don't commit .github/workflows/redirect-pr-to-forgejo.yaml
#   --only <owner/name>   restrict to a single repo (can be repeated)
#   --refresh-banner      regenerate .github/README.md even if it already exists

set -euo pipefail

MANIFEST="${FORGEJO_MIRROR_MANIFEST:-/etc/forgejo-mirror/manifest.json}"
DB="${FORGEJO_DB:-/var/lib/forgejo/data/forgejo.db}"
TEA_LOGIN="${TEA_LOGIN:-harivan}"
FORGEJO_HOST="git.harivan.sh"
DRY=0
DO_META=1
DO_BANNER=1
DO_REDIRECT=1
FORCE_BANNER=0
declare -a ONLY=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --skip-metadata) DO_META=0 ;;
    --skip-banner) DO_BANNER=0 ;;
    --skip-redirect) DO_REDIRECT=0 ;;
    --refresh-banner) FORCE_BANNER=1 ;;
    --only) shift; ONLY+=("$1") ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

log()  { printf '%s %s\n' "[$(date +%H:%M:%S)]" "$*"; }
warn() { printf '%s WARN  %s\n' "[$(date +%H:%M:%S)]" "$*" >&2; }
die()  { printf '%s FATAL %s\n' "[$(date +%H:%M:%S)]" "$*" >&2; exit 1; }

tea_api() { tea api --login "$TEA_LOGIN" "$@"; }
gh_api()  { gh api "$@"; }

# Base64 helper for forgejo's content API (it wants raw base64, single-line).
b64() {
  if base64 --version 2>/dev/null | grep -q GNU; then
    base64 -w0
  else
    base64 | tr -d '\n'
  fi
}

# Encode a string for use inside a JSON string value (escape backslashes,
# double quotes, control chars). Uses jq for correctness.
json_str() { jq -Rs . <<<"$1"; }

REDIRECT_WORKFLOW=$(cat <<'YAML'
name: Redirect PRs to Forgejo

on:
  pull_request_target:
    types: [opened, reopened]

permissions:
  pull-requests: write
  issues: write

jobs:
  redirect:
    runs-on: ubuntu-latest
    steps:
      - name: Comment and close
        uses: actions/github-script@v7
        with:
          script: |
            const forgejoUrl = `https://git.harivan.sh/${context.repo.owner}/${context.repo.repo}`;
            const body = [
              'Thanks for the contribution.',
              '',
              `This GitHub repo is a read-only mirror. Please re-open this pull request at ${forgejoUrl}.`,
            ].join('\n');
            await github.rest.issues.createComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.payload.pull_request.number,
              body,
            });
            await github.rest.pulls.update({
              owner: context.repo.owner,
              repo: context.repo.repo,
              pull_number: context.payload.pull_request.number,
              state: 'closed',
            });
YAML
)

# Pull the root README from forgejo (if present), prepend the mirror banner,
# and emit on stdout.
build_banner_readme() {
  local owner="$1" name="$2"
  local root
  if root=$(tea_api "/repos/$owner/$name/raw/README.md" 2>/dev/null) && [ -n "$root" ]; then
    :
  elif root=$(tea_api "/repos/$owner/$name/raw/readme.md" 2>/dev/null) && [ -n "$root" ]; then
    :
  else
    root=""
  fi

  if [ -z "$root" ]; then
    # Fallback when forgejo has no README: write a banner-only file.
    cat <<EOF
# $name

> [!IMPORTANT]
> This is a read-only mirror of <https://$FORGEJO_HOST/$owner/$name>. Use Forgejo for issues, pull requests, and active development.
EOF
    return
  fi

  local header rest
  header=$(printf '%s' "$root" | head -n 1)
  rest=$(printf '%s' "$root" | tail -n +2)

  cat <<EOF
$header

> [!IMPORTANT]
> This is a read-only mirror of <https://$FORGEJO_HOST/$owner/$name>. Use Forgejo for issues, pull requests, and active development.
$rest
EOF
}

# PUT/POST a file into forgejo's contents API. Idempotent: looks up existing
# sha and uses PUT-with-sha to replace, or POST to create.
put_forgejo_file() {
  local owner="$1" name="$2" path="$3" message="$4" content="$5"
  local b64content
  b64content=$(printf '%s' "$content" | b64)

  local existing_sha
  existing_sha=$(tea_api "/repos/$owner/$name/contents/$path" 2>/dev/null \
    | jq -r '.sha // empty' || true)

  local body
  if [ -n "$existing_sha" ]; then
    body=$(jq -nc \
      --arg message "$message" \
      --arg content "$b64content" \
      --arg sha "$existing_sha" \
      '{message:$message, content:$content, sha:$sha}')
    log "    PUT  $path (sha=$existing_sha)"
  else
    body=$(jq -nc \
      --arg message "$message" \
      --arg content "$b64content" \
      '{message:$message, content:$content}')
    log "    POST $path"
  fi
  if [ "$DRY" = "1" ]; then
    return 0
  fi
  printf '%s' "$body" \
    | tea_api -X POST "/repos/$owner/$name/contents/$path" -H "Content-Type: application/json" --input - >/dev/null
}

# True if file at path is byte-identical to provided content.
forgejo_file_equals() {
  local owner="$1" name="$2" path="$3" content="$4"
  local remote
  remote=$(tea_api "/repos/$owner/$name/raw/$path" 2>/dev/null) || return 1
  [ "$remote" = "$content" ]
}

trigger_sync() {
  local owner="$1" name="$2"
  if [ "$DRY" = "1" ]; then
    log "    DRY trigger push_mirrors-sync"
    return 0
  fi
  tea_api -X POST "/repos/$owner/$name/push_mirrors-sync" >/dev/null \
    || warn "    $owner/$name: push_mirrors-sync trigger failed"
}

apply_github_metadata() {
  local owner="$1" name="$2"

  local current
  current=$(gh_api "/repos/$owner/$name" 2>/dev/null) \
    || { warn "    gh api fetch failed; skipping metadata"; return 0; }

  local archived has_issues has_wiki has_projects description homepage
  archived=$(printf '%s' "$current"  | jq -r '.archived')
  has_issues=$(printf '%s' "$current"| jq -r '.has_issues')
  has_wiki=$(printf '%s' "$current"  | jq -r '.has_wiki')
  has_projects=$(printf '%s' "$current"| jq -r '.has_projects')
  description=$(printf '%s' "$current"| jq -r '.description // ""')
  homepage=$(printf '%s' "$current"  | jq -r '.homepage // ""')

  local forgejo_url="https://$FORGEJO_HOST/$owner/$name"
  local desc_prefix="[mirror of $FORGEJO_HOST/$owner/$name]"
  local new_desc="$description"
  case "$description" in
    "$desc_prefix"*) ;;                    # already prefixed
    "")              new_desc="$desc_prefix" ;;
    *)               new_desc="$desc_prefix $description" ;;
  esac

  local needs_patch=0
  local -a patch_args=()
  if [ "$archived" = "true" ]; then
    patch_args+=( -F "archived=false" )
    needs_patch=1
  fi
  if [ "$has_issues" = "true" ]; then
    patch_args+=( -F "has_issues=false" )
    needs_patch=1
  fi
  if [ "$has_wiki" = "true" ]; then
    patch_args+=( -F "has_wiki=false" )
    needs_patch=1
  fi
  if [ "$has_projects" = "true" ]; then
    patch_args+=( -F "has_projects=false" )
    needs_patch=1
  fi
  if [ "$homepage" != "$forgejo_url" ]; then
    patch_args+=( -F "homepage=$forgejo_url" )
    needs_patch=1
  fi
  if [ "$new_desc" != "$description" ]; then
    patch_args+=( -F "description=$new_desc" )
    needs_patch=1
  fi

  if [ "$needs_patch" = "0" ]; then
    log "    metadata: already up to date"
    return 0
  fi

  log "    metadata: PATCH ${patch_args[*]}"
  if [ "$DRY" = "1" ]; then
    return 0
  fi
  gh_api -X PATCH "/repos/$owner/$name" "${patch_args[@]}" >/dev/null \
    || warn "    gh api PATCH failed"
}

main() {
  command -v jq   >/dev/null 2>&1 || die "missing jq"
  command -v tea  >/dev/null 2>&1 || die "missing tea"
  command -v gh   >/dev/null 2>&1 || die "missing gh"
  command -v base64 >/dev/null 2>&1 || die "missing base64"

  [ -r "$MANIFEST" ] || die "manifest not readable: $MANIFEST"
  log "manifest: $MANIFEST"
  [ "$DRY" = "1" ] && log "DRY RUN"

  local owned_owner
  owned_owner=$(jq -r '.owned_owner' "$MANIFEST")

  local repos
  if [ "${#ONLY[@]}" -gt 0 ]; then
    repos=$(printf '%s\n' "${ONLY[@]}")
  else
    command -v sqlite3 >/dev/null 2>&1 || die "missing sqlite3 (needed to discover push-mirror targets)"
    [ -r "$DB" ] || die "forgejo db not readable: $DB (need root)"
    repos=$(sqlite3 -bail -batch "$DB" "SELECT DISTINCT u.lower_name || '/' || r.lower_name FROM push_mirror p JOIN repository r ON r.id=p.repo_id JOIN user u ON u.id=r.owner_id WHERE u.lower_name='$owned_owner' ORDER BY 1;")
  fi

  local needs_sync=0
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    local owner name
    owner="${path%%/*}"; name="${path##*/}"
    log "$path"

    if [ "$DO_META" = "1" ]; then
      apply_github_metadata "$owner" "$name"
    fi

    if [ "$DO_BANNER" = "1" ]; then
      local banner
      banner=$(build_banner_readme "$owner" "$name")
      if [ "$FORCE_BANNER" = "0" ] && forgejo_file_equals "$owner" "$name" ".github/README.md" "$banner"; then
        log "    .github/README.md: unchanged"
      else
        put_forgejo_file "$owner" "$name" ".github/README.md" \
          "docs(.github): mirror banner README" \
          "$banner"
        needs_sync=1
      fi
    fi

    if [ "$DO_REDIRECT" = "1" ]; then
      if forgejo_file_equals "$owner" "$name" \
          ".github/workflows/redirect-pr-to-forgejo.yaml" "$REDIRECT_WORKFLOW"; then
        log "    redirect workflow: unchanged"
      else
        put_forgejo_file "$owner" "$name" \
          ".github/workflows/redirect-pr-to-forgejo.yaml" \
          "ci(.github): add redirect-pr-to-forgejo workflow" \
          "$REDIRECT_WORKFLOW"
        needs_sync=1
      fi
    fi

    if [ "$needs_sync" = "1" ]; then
      trigger_sync "$owner" "$name"
      needs_sync=0
    fi
  done <<< "$repos"

  log "done"
}

main "$@"
