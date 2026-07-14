#!/bin/bash
sketchybar --set "$NAME" label="$(date '+%a %d %b %l:%M %p' | tr -s ' ')"
