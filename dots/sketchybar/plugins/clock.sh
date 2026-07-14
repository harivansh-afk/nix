#!/bin/bash
# icon carries the date, label carries the time (styled pink in the rc)
time="$(date '+%l:%M %p')"
sketchybar --set "$NAME" icon="$(date '+%a %d %b')" label="${time# }"
