#!/bin/bash

cores="$(sysctl -n hw.logicalcpu 2>/dev/null)"
[ -n "$cores" ] || cores=1

cpu="$(ps -A -o %cpu= | awk -v cores="$cores" '
  { total += $1 }
  END {
    used = total / cores
    if (used > 100) used = 100
    printf "%.0f", used
  }
')"

memory="$(memory_pressure -Q 2>/dev/null | awk '
  /System-wide memory free percentage:/ {
    gsub("%", "", $5)
    print 100 - $5
    exit
  }
')"

args=()
[ -n "$cpu" ] && args+=(--set cpu label="${cpu}%")
[ -n "$memory" ] && args+=(--set memory label="${memory}%")
[ "${#args[@]}" -gt 0 ] && sketchybar "${args[@]}"
