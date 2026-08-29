#!/usr/bin/env bash
# Inputs from the nix wrapper: LOGIN_ITEMS and PLISTS, pipe-delimited
# allowlists with a leading and trailing pipe.
set -u
PATH=/usr/bin:/bin
log_file="$HOME/Library/Logs/startup-guard.log"

log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >>"$log_file"; }
notify() {
  osascript -e "display notification \"$1\" with title \"startup-guard\"" 2>/dev/null || true
}

items=$(osascript -e 'tell application "System Events" to get the name of every login item' 2>>"$log_file" | tr ',' '\n' | sed 's/^ *//;s/ *$//')
while IFS= read -r item; do
  [ -n "$item" ] || continue
  case "$LOGIN_ITEMS" in
  *"|$item|"*) ;;
  *)
    if osascript -e "tell application \"System Events\" to delete (every login item whose name is \"$item\")" 2>>"$log_file"; then
      log "deleted undeclared login item: $item"
      notify "removed undeclared login item: $item"
    else
      log "FAILED to delete login item: $item (Automation permission?)"
    fi
    ;;
  esac
done <<<"$items"

for dir in "$HOME/Library/LaunchAgents" /Library/LaunchAgents /Library/LaunchDaemons; do
  [ -d "$dir" ] || continue
  for f in "$dir"/*.plist; do
    [ -e "$f" ] || continue
    base=$(basename "$f")
    case "$base" in
    org.nixos.*) continue ;;
    esac
    case "$PLISTS" in
    *"|$base|"*) continue ;;
    *)
      log "UNDECLARED plist: $f"
      notify "undeclared startup plist: $base"
      ;;
    esac
  done
done
