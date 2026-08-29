#!/usr/bin/env bash
# Recent messages -> staging/gmail/<id>.md (headers + snippet). Exits clean
# until gws is authenticated.
set -uo pipefail
# shellcheck source=gws-env.sh
. "$GWS_ENV"
out="$KB_STAGING_DIR/gmail"
mkdir -p "$out"
if ! "$GWS" gmail users getProfile --params '{"userId":"me"}' >/dev/null 2>&1; then
  echo "gws not authenticated; skipping gmail ingest"
  exit 0
fi
ids=$("$GWS" gmail users messages list --params '{"userId":"me","maxResults":50}' 2>/dev/null |
  jq -r '.messages[]?.id' 2>/dev/null) || ids=""
n=0
for id in $ids; do
  f="$out/$id.md"
  [ -f "$f" ] && continue
  msg=$("$GWS" gmail users messages get \
    --params "{\"userId\":\"me\",\"id\":\"$id\",\"format\":\"full\"}" 2>/dev/null) || continue
  subj=$(printf '%s' "$msg" | jq -r '.payload.headers[]? | select(.name=="Subject") | .value' 2>/dev/null | head -1)
  frm=$(printf '%s' "$msg" | jq -r '.payload.headers[]? | select(.name=="From") | .value' 2>/dev/null | head -1)
  dt=$(printf '%s' "$msg" | jq -r '.payload.headers[]? | select(.name=="Date") | .value' 2>/dev/null | head -1)
  snip=$(printf '%s' "$msg" | jq -r '.snippet // ""' 2>/dev/null)
  {
    printf '# %s\n\n' "${subj:-(no subject)}"
    printf -- '- From: %s\n- Date: %s\n- Source: gmail\n\n' "$frm" "$dt"
    printf '%s\n' "$snip"
  } >"$f"
  n=$((n + 1))
done
echo "gmail: wrote $n new message(s) to $out"
