#!/usr/bin/env bash
# Snapshot forge.ix.dev main into the forgejo indexable-inc/ix repo. The
# forge speaks no git protocol, so a jj-ix workspace materializes main and a
# plain git clone pushes "snapshot: forge main @ <rev>" commits over localhost.
#
# Bootstrap state (created by hand; `jj-ix ix clone` is refused by the
# forge's protected-main gate, so it cannot be recreated here):
#   $STATE_DIR/ws   jj-ix workspace "forgejo-mirror" off ~/Documents/Git/indexable/ix
#   $STATE_DIR/git  git clone of the forgejo repo, main checked out
#
# Environment: STATE_DIR, JJ (jj-ix binary), TOKEN_FILE (forgejo API token).
set -euo pipefail

ws="$STATE_DIR/ws"
gitdir="$STATE_DIR/git"

[ -e "$ws/.jj/repo" ] || {
  echo "missing jj workspace at $ws (see forge-snapshot-mirror.sh)"
  exit 1
}
[ -d "$gitdir/.git" ] || {
  echo "missing git clone at $gitdir"
  exit 1
}

tip=$("$JJ" -R "$ws" --ignore-working-copy log -r main --no-graph \
  -T 'commit_id.short(12) ++ "\t" ++ change_id.short(12) ++ "\t" ++ description.first_line()')
rev=$(printf '%s' "$tip" | cut -f1)
change=$(printf '%s' "$tip" | cut -f2)

TOK=$(cat "$TOKEN_FILE")
export TOK
# shellcheck disable=SC2016 # $TOK expands inside git's helper, not here
authgit() { git -c credential.helper='!f() { echo username=harivansh-afk; echo "password=$TOK"; }; f' "$@"; }

# Re-anchor on whatever forgejo serves so a foreign push or a crashed run
# cannot wedge this one.
authgit -C "$gitdir" fetch -q origin main
git -C "$gitdir" checkout -q main
git -C "$gitdir" reset -q --hard origin/main

subject="snapshot: forge main @ $rev (change $change)"
last=$(git -C "$gitdir" log -1 --format=%s)
if [ "$last" = "$subject" ]; then
  echo "up to date @ $rev"
  exit 0
fi

# The forge refuses ops transiently on op-head races and the workspace goes
# stale when the operator checkout advances; retry through both.
ok=0
for attempt in 1 2 3; do
  if "$JJ" -R "$ws" new main; then
    ok=1
    break
  fi
  echo "jj new main failed (attempt $attempt); trying update-stale + retry"
  "$JJ" -R "$ws" workspace update-stale || true
  sleep 10
done
[ "$ok" = 1 ] || {
  echo "could not advance the mirror workspace to main"
  exit 1
}

# Snapshot what got materialized (@-); main may have advanced since.
tip=$("$JJ" -R "$ws" --ignore-working-copy log -r '@-' --no-graph \
  -T 'commit_id.short(12) ++ "\t" ++ change_id.short(12) ++ "\t" ++ description.first_line()')
rev=$(printf '%s' "$tip" | cut -f1)
change=$(printf '%s' "$tip" | cut -f2)
desc=$(printf '%s' "$tip" | cut -f3-)
subject="snapshot: forge main @ $rev (change $change)"

rsync -a --delete --exclude=/.jj --exclude=/.git "$ws/" "$gitdir/"

cd "$gitdir"
# -f: jj tracks files that upstream .gitignores would hide from `git add -A`.
git add -A -f
if git diff --cached --quiet; then
  echo "tree unchanged at $rev; nothing to push"
  exit 0
fi

git -c user.name='Harivansh Rathi' -c user.email='rathiharivansh@gmail.com' \
  commit -q -m "$subject" -m "Tree snapshot of the jj-native ix forge (SOT), taken from
https://forge.ix.dev:8447/rpc repo ix.

Forge commit: $rev (main)
$desc"

authgit push -q origin main
echo "pushed $subject"
