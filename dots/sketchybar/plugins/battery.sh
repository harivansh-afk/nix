#!/bin/bash
# Battery percentage; "chg" prefix on AC power, red label when low.

source "$CONFIG_DIR/themes/current"

batt=$(pmset -g batt)
pct=$(printf '%s' "$batt" | grep -Eo '[0-9]+%' | head -1 | tr -d '%')
[ -n "$pct" ] || exit 0

icon=bat
case "$batt" in
*"AC Power"*) icon=chg ;;
esac

color="$TEXT_COLOR"
if [ "$pct" -le 15 ] && [ "$icon" = "bat" ]; then
  color="$RED_COLOR"
fi

sketchybar --set "$NAME" icon="$icon" label="${pct}%" label.color="$color"
