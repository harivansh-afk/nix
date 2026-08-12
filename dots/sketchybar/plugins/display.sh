#!/bin/bash
# Resolution watchdog (attached to the hidden display_monitor item, plus
# display_change/system_woke). BAR_HEIGHT is measured from
# NSScreen.safeAreaInsets.top at rc time, but sketchybar fires no event when
# the resolution changes - so this compares the daemon's own display frames
# (a ~ms socket query, no swift spawn) against a stamp and reloads the config
# when they drift, which re-measures everything. First run just seeds the
# stamp: the rc measured moments ago.

stamp_dir="${XDG_CACHE_HOME:-$HOME/.cache}/sketchybar"
stamp="$stamp_dir/displays"

current="$(sketchybar --query displays)"
[ -n "$current" ] || exit 0

previous="$(cat "$stamp" 2>/dev/null)"
if [ "$current" != "$previous" ]; then
  mkdir -p "$stamp_dir"
  printf '%s' "$current" >"$stamp"
  [ -n "$previous" ] && sketchybar --reload
fi
