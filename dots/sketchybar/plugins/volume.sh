#!/bin/bash
# Output volume: click toggles mute, scroll adjusts.

source "$CONFIG_DIR/themes/current"

case "$SENDER" in
mouse.clicked)
  osascript -e 'set volume output muted not (output muted of (get volume settings))'
  ;;
mouse.scrolled)
  osascript -e "set volume output volume ((output volume of (get volume settings)) + ${SCROLL_DELTA:-0})"
  ;;
esac

vol=$(osascript -e 'output volume of (get volume settings)')
muted=$(osascript -e 'output muted of (get volume settings)')

if [ "$muted" = "true" ]; then
  sketchybar --set "$NAME" label="mute" label.color="$MUTED_COLOR"
else
  sketchybar --set "$NAME" label="${vol}%" label.color="$TEXT_COLOR"
fi
