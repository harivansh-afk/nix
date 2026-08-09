# Service lifecycle for long-lived launchd services (user-decided 2026-08-09).
#
# Two pieces:
#
# 1. aerospace runs as a DECLARED nix-darwin agent (org.nixos.aerospace).
#    It used to be started by an orphaned home-manager plist
#    (org.nix-community.home.aerospace) that hardcoded an old store path
#    with KeepAlive=true: rebuilds moved pkgs.aerospace forward but the
#    running WM kept executing the stale binary (observed: the plist pinned
#    aerospace 0.20.3 while nixpkgs had moved on, process 9d16h old).
#    nix-darwin rewrites this plist on every switch, so the binary path
#    follows the package; postActivation boots the orphan out once.
#
# 2. A scheduled refresh restarts each managed service at least once every
#    2 days. Mechanism: a daily launchd fire plus per-service stamp files;
#    a service is kickstarted only when its stamp is older than 40h, which
#    on a daily schedule produces an every-2nd-day cadence and self-heals
#    across missed fires (laptop asleep or powered off at 04:30). Wall
#    times: 04:30 user agents, 04:35 system daemons.
#
# WindowServer is deliberately NOT restarted (killing it ends the login
# session); the user-level run only logs its rss/%cpu on every fire so
# there is measured data on when a logout/reboot is due (777MB rss and
# 47-91% cpu observed after 24d uptime when this module was written).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  user = config.system.primaryUser;
  maxAgeHours = 40;

  # gui-domain agents, restarted in list order: aerospace must be answering
  # again before sketchybar restarts (sketchybarrc builds the workspace
  # tabs from aerospace queries at startup).
  userRefresh = pkgs.writeShellScript "service-refresh-user" ''
    set -u
    stamp_dir="$HOME/Library/Application Support/service-refresh"
    log_file="$HOME/Library/Logs/service-refresh.log"
    mkdir -p "$stamp_dir" "$(dirname "$log_file")"
    log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >>"$log_file"; }
    now=$(date +%s)
    uid=$(id -u)
    for label in org.nixos.aerospace org.nixos.sketchybar; do
      stamp="$stamp_dir/$label"
      last=0
      [ -f "$stamp" ] && last=$(cat "$stamp")
      if [ $((now - last)) -lt $((${toString maxAgeHours} * 3600)) ]; then
        log "skip $label (age $((now - last))s < ${toString maxAgeHours}h)"
        continue
      fi
      if /bin/launchctl kickstart -k "gui/$uid/$label" 2>>"$log_file"; then
        date +%s >"$stamp"
        log "kickstarted $label"
      else
        log "FAILED to kickstart $label"
      fi
      if [ "$label" = org.nixos.aerospace ]; then
        tries=0
        until ${pkgs.aerospace}/bin/aerospace list-workspaces --focused >/dev/null 2>&1 || [ "$tries" -ge 20 ]; do
          sleep 1
          tries=$((tries + 1))
        done
        log "aerospace answering after $tries s"
      fi
    done
    ws_pid=$(pgrep -x WindowServer | head -1) && log "windowserver rss_kb=$(ps -o rss= -p "$ws_pid" | tr -d ' ') pcpu=$(ps -o %cpu= -p "$ws_pid" | tr -d ' ')"
  '';

  systemRefresh = pkgs.writeShellScript "service-refresh-system" ''
    set -u
    stamp_dir="/var/lib/service-refresh"
    log_file="/Library/Logs/service-refresh-system.log"
    mkdir -p "$stamp_dir"
    log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >>"$log_file"; }
    now=$(date +%s)
    # com.tailscale.tailscaled is the nix-darwin services.tailscale daemon
    # (macos.nix). The Tailscale.app network extension is NOT touched: its
    # lifecycle belongs to the app.
    for label in com.tailscale.tailscaled; do
      stamp="$stamp_dir/$label"
      last=0
      [ -f "$stamp" ] && last=$(cat "$stamp")
      if [ $((now - last)) -lt $((${toString maxAgeHours} * 3600)) ]; then
        log "skip $label (age $((now - last))s < ${toString maxAgeHours}h)"
        continue
      fi
      if /bin/launchctl kickstart -k "system/$label" 2>>"$log_file"; then
        date +%s >"$stamp"
        log "kickstarted $label"
      else
        log "FAILED to kickstart $label"
      fi
    done
  '';
in
{
  launchd.user.agents.aerospace = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        "/bin/wait4path /nix/store && exec ${pkgs.aerospace}/Applications/AeroSpace.app/Contents/MacOS/AeroSpace"
      ];
      KeepAlive = true;
      RunAtLoad = true;
      StandardOutPath = "/tmp/aerospace.log";
      StandardErrorPath = "/tmp/aerospace.err.log";
    };
  };

  launchd.user.agents.service-refresh = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        "/bin/wait4path /nix/store && exec ${userRefresh}"
      ];
      StartCalendarInterval = [
        {
          Hour = 4;
          Minute = 30;
        }
      ];
      RunAtLoad = false;
      StandardErrorPath = "/tmp/service-refresh.err.log";
    };
  };

  launchd.daemons.service-refresh = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        "/bin/wait4path /nix/store && exec ${systemRefresh}"
      ];
      StartCalendarInterval = [
        {
          Hour = 4;
          Minute = 35;
        }
      ];
      RunAtLoad = false;
      StandardErrorPath = "/tmp/service-refresh-system.err.log";
    };
  };

  # One-time migration: boot out the orphaned home-manager aerospace agent
  # (see header comment). Idempotent: no-op once the plist is gone.
  system.activationScripts.postActivation.text = lib.mkAfter ''
    hm_plist="/Users/${user}/Library/LaunchAgents/org.nix-community.home.aerospace.plist"
    if [ -f "$hm_plist" ]; then
      uid=$(/usr/bin/id -u ${user})
      /bin/launchctl bootout "gui/$uid/org.nix-community.home.aerospace" 2>/dev/null || true
      /bin/rm -f "$hm_plist"
      echo "service-refresh: removed orphaned home-manager aerospace agent" >&2
    fi
  '';
}
