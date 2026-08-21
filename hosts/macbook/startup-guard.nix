# Startup guard: keeps launch-at-login state equal to what this file declares.
#
# macOS lets any app register itself into System Settings > Login Items
# (SMAppService) and any installer drop plists into /Library - both invisible
# to nix. This agent (daily + at login + reloaded on every switch) enforces:
#
# - Login items: anything NOT in `allowedLoginItems` is DELETED via System
#   Events (verified working against SMAppService items 2026-08-21, same
#   mechanism Homebrew casks use on uninstall). Want an app at login? Add it
#   here or to apps.nix, switch.
# - launchd plists: anything in ~/Library/LaunchAgents, /Library/LaunchAgents
#   or /Library/LaunchDaemons that is not org.nixos.* and not in
#   `allowedPlists` triggers a macOS notification + a log line
#   (~/Library/Logs/startup-guard.log). Not auto-deleted: a new legit
#   installer should be a conscious allowlist edit, not a silent kill.
#
# First run may prompt once to let the agent control System Events
# (Automation permission); grant it or login-item enforcement logs failures.
{ config, pkgs, ... }:
let
  allowedLoginItems = [
    "Raycast Beta" # manual install, no cask exists; self-updates
    "PastePal"
  ];

  # Non-nix plists that are allowed to exist, by filename.
  allowedPlists = [
    # nix-darwin units without the org.nixos prefix
    "limit.maxfiles.plist"
    # Determinate Nix owns the daemon
    "systems.determinate.nix-daemon.plist"
    "systems.determinate.nix-installer.nix-hook.plist"
    "systems.determinate.nix-store.plist"
    # nix-darwin store mount
    "org.nixos.darwin-store.plist"
  ];

  guard = pkgs.writeShellScript "startup-guard" ''
    set -u
    PATH=/usr/bin:/bin
    log_file="$HOME/Library/Logs/startup-guard.log"
    log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >>"$log_file"; }
    notify() {
      osascript -e "display notification \"$1\" with title \"startup-guard\"" 2>/dev/null || true
    }

    # --- login items: enforce ---
    allowed_items='|${builtins.concatStringsSep "|" allowedLoginItems}|'
    items=$(osascript -e 'tell application "System Events" to get the name of every login item' 2>>"$log_file" | tr ',' '\n' | sed 's/^ *//;s/ *$//')
    if [ -n "$items" ]; then
      while IFS= read -r item; do
        [ -n "$item" ] || continue
        case "$allowed_items" in
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
    fi

    # --- launchd plists: warn ---
    allowed_plists='|${builtins.concatStringsSep "|" allowedPlists}|'
    for dir in "$HOME/Library/LaunchAgents" /Library/LaunchAgents /Library/LaunchDaemons; do
      [ -d "$dir" ] || continue
      for f in "$dir"/*.plist; do
        [ -e "$f" ] || continue
        base=$(basename "$f")
        case "$base" in
          org.nixos.*) continue ;;
        esac
        case "$allowed_plists" in
          *"|$base|"*) continue ;;
          *)
            log "UNDECLARED plist: $f"
            notify "undeclared startup plist: $base"
            ;;
        esac
      done
    done
  '';
in
{
  launchd.user.agents.startup-guard.serviceConfig = {
    ProgramArguments = [
      "/bin/sh"
      "-c"
      "/bin/wait4path /nix/store && exec ${guard}"
    ];
    # at login and on every switch (plist changes whenever the guard or the
    # allowlists change), plus a daily sweep for mid-session installers
    RunAtLoad = true;
    StartCalendarInterval = [
      {
        Hour = 4;
        Minute = 40;
      }
    ];
    StandardOutPath = "/Users/${config.system.primaryUser}/Library/Logs/startup-guard.log";
    StandardErrorPath = "/Users/${config.system.primaryUser}/Library/Logs/startup-guard.log";
  };
}
