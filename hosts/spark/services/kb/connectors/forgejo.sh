#!/usr/bin/env bash
# Own repos -> staging/forgejo/ (READMEs + open issues).
set -uo pipefail
out="$KB_STAGING_DIR/forgejo"
mkdir -p "$out"
base="https://git.harivan.sh/api/v1"
tok=$(cat /run/secrets/forgejo-token 2>/dev/null) || {
  echo "no forgejo token; skipping"
  exit 0
}
auth="Authorization: token $tok"
repos=$(curl -fsS -H "$auth" "$base/user/repos?limit=50" 2>/dev/null |
  jq -r '.[].full_name' 2>/dev/null) || {
  echo "forgejo API unreachable; skipping"
  exit 0
}
n=0
for r in $repos; do
  safe=$(printf '%s' "$r" | tr '/' '_')
  readme=$(curl -fsS -H "$auth" "$base/repos/$r/contents/README.md" 2>/dev/null |
    jq -r '.content // empty' 2>/dev/null | base64 -d 2>/dev/null) || readme=""
  [ -n "$readme" ] && printf '# %s (README)\n\n%s\n' "$r" "$readme" >"$out/${safe}_README.md"
  issues=$(curl -fsS -H "$auth" "$base/repos/$r/issues?state=open&limit=50&type=issues" 2>/dev/null |
    jq -r '.[] | "## #\(.number) \(.title)\n\n\(.body // "")\n"' 2>/dev/null) || issues=""
  [ -n "$issues" ] && printf '# %s (open issues)\n\n%s\n' "$r" "$issues" >"$out/${safe}_issues.md"
  n=$((n + 1))
done
echo "forgejo: synced $n repo(s) to $out"
