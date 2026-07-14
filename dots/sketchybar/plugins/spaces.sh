#!/bin/bash
# Batch renderer for the workspace tabs. Runs once per event (attached to the
# hidden spaces_monitor item): two aerospace calls total, one icon_map.sh call
# per occupied workspace, one sketchybar apply - instead of a process per tab.
# FOCUSED_WORKSPACE arrives with the aerospace_workspace_change trigger.
# Focused tab: accent background with dark content. Occupied: surface
# background. Empty: hidden.

source "$CONFIG_DIR/themes/current"

focused="${FOCUSED_WORKSPACE:-$(aerospace list-workspaces --focused)}"
windows="$(aerospace list-windows --all --format '%{workspace}|%{app-name}' 2>/dev/null)"

args=()
# workspaces 1-9, matching the aerospace.toml bindings
for sid in 1 2 3 4 5 6 7 8 9; do
  # first app only: one icon per tab, even when several apps are open
  app="$(printf '%s\n' "$windows" | awk -F'|' -v w="$sid" '$1 == w { print $2 }' | sort -u | head -1)"

  icons=""
  if [ -n "$app" ]; then
    # trim the trailing whitespace icon_map emits
    icons="$(icon_map.sh "$app")"
    icons="${icons%"${icons##*[![:space:]]}"}"
  fi

  label_drawing=off
  [ -n "$icons" ] && label_drawing=on

  # background.color is set explicitly in every branch: item properties
  # persist in the daemon, so relying on defaults leaves stale colors behind
  # (e.g. a tab frozen on the old accent after a config change)
  if [ "$sid" = "$focused" ]; then
    # same surface background as every tab; only the number lights up pink
    # (the mux pointer purple)
    args+=(--set "space.$sid" drawing=on
      background.color="$SURFACE_COLOR"
      icon.color="$PINK_COLOR"
      label="$icons"
      label.drawing="$label_drawing"
      label.color="$BRIGHT_COLOR")
  elif [ -n "$icons" ]; then
    args+=(--set "space.$sid" drawing=on
      background.color="$SURFACE_COLOR"
      icon.color="$MUTED_COLOR"
      label="$icons"
      label.drawing=on
      label.color="$TEXT_COLOR")
  else
    args+=(--set "space.$sid" drawing=off)
  fi
done

sketchybar "${args[@]}"
