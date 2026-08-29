#!/usr/bin/env bash
# Next 90 days of events -> staging/calendar/<id>.md.
set -uo pipefail
# shellcheck source=gws-env.sh
. "$GWS_ENV"
out="$KB_STAGING_DIR/calendar"
mkdir -p "$out"
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
future=$(date -u -d '+90 days' +%Y-%m-%dT%H:%M:%SZ)
params=$(printf '{"calendarId":"primary","timeMin":"%s","timeMax":"%s","singleEvents":true,"orderBy":"startTime","maxResults":250}' "$now" "$future")
events=$("$GWS" calendar events list --params "$params" 2>/dev/null) || {
  echo "gws not authenticated or calendar unavailable; skipping"
  exit 0
}
count=$(printf '%s' "$events" | jq '.items | length' 2>/dev/null) || count=0
[ "$count" = "null" ] && count=0
i=0
while [ "$i" -lt "$count" ]; do
  ev=$(printf '%s' "$events" | jq ".items[$i]")
  id=$(printf '%s' "$ev" | jq -r '.id')
  summary=$(printf '%s' "$ev" | jq -r '.summary // "(no title)"')
  start=$(printf '%s' "$ev" | jq -r '.start.dateTime // .start.date // ""')
  end=$(printf '%s' "$ev" | jq -r '.end.dateTime // .end.date // ""')
  loc=$(printf '%s' "$ev" | jq -r '.location // ""')
  desc=$(printf '%s' "$ev" | jq -r '.description // ""')
  {
    printf '# %s\n\n' "$summary"
    printf -- '- Start: %s\n- End: %s\n- Location: %s\n- Source: calendar\n\n' "$start" "$end" "$loc"
    printf '%s\n' "$desc"
  } >"$out/$id.md"
  i=$((i + 1))
done
echo "calendar: wrote $count event(s) to $out"
