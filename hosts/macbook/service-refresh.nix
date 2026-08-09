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
# 2. A scheduled refresh restarts every long-running managed service at
#    least once every 2 days. The service set is DERIVED, not hardcoded:
#    every launchd unit this config declares whose KeepAlive is set (i.e.
#    meant to run forever) is covered automatically - a new KeepAlive
#    service added anywhere in the config joins the rotation with no edit
#    here. One-shots (RunAtLoad installers, the open-* login apps, this
#    module's own refresh timers) have no KeepAlive and are skipped.
#    Mechanism: a daily launchd fire plus per-service stamp files; a
#    service is refreshed only when its stamp is older than 40h, which on
#    a daily schedule produces an every-2nd-day cadence and self-heals
#    across missed fires (laptop asleep or powered off at 04:30). Wall
#    times: 04:30 user agents, 04:35 system daemons.
#    Restarts are graceful: SIGTERM first, 15s for the service to exit on
#    its own terms (KeepAlive brings it straight back), forced kickstart
#    only if TERM was ignored.
#
# WindowServer is deliberately NOT restarted (killing it ends the login
# session - there is no zero-downtime path to a fresh WindowServer, only
# logout/reboot); the user-level run logs its rss/%cpu on every fire so
# there is measured data on when a reboot is due (777MB rss and 47-91%
# cpu observed after 24d uptime when this module was written).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  user = config.system.primaryUser;
  maxAgeHours = 40;

  # A unit is long-running when it declares KeepAlive (bool true or a
  # conditional attrset). nix-darwin defaults every unset serviceConfig key
  # to null, so null must be treated as "not declared" - a naive `!= false`
  # check would pull in every unit on the system, including nix-darwin's
  # own activate-system daemon (verified by eval: its KeepAlive is null).
  labelOf = name: cfg: cfg.serviceConfig.Label or "org.nixos.${name}";
  longRunning = lib.filterAttrs (
    _name: cfg:
    let
      k = cfg.serviceConfig.KeepAlive or null;
    in
    k != null && k != false
  );
  agentLabels = lib.mapAttrsToList labelOf (longRunning config.launchd.user.agents);
  # Long-running daemons that declare no KeepAlive still need covering:
  # tailscaled runs forever but its plist carries no KeepAlive key at all
  # (verified against /Library/LaunchDaemons/com.tailscale.tailscaled.plist),
  # so the derived filter cannot see it. refresh_unit handles both shapes:
  # KeepAlive units come back on their own after TERM, KeepAlive-less units
  # get an explicit kickstart once stopped.
  extraDaemonLabels = [ "com.tailscale.tailscaled" ];
  daemonLabels = lib.unique (
    lib.mapAttrsToList labelOf (longRunning config.launchd.daemons) ++ extraDaemonLabels
  );

  # aerospace restarts first: sketchybar (and anything else querying the WM)
  # must find it answering again, so the script gates on a readiness poll
  # right after it.
  orderedAgentLabels = [
    "org.nixos.aerospace"
  ]
  ++ lib.filter (l: l != "org.nixos.aerospace") agentLabels;

  # Graceful refresh shared by both scripts. $1 = launchctl target
  # (gui/UID/label or system/label). SIGTERM, wait up to 15s; if the old
  # pid is still there the TERM was ignored -> forced kickstart; if the
  # unit is stopped and KeepAlive has not brought it back -> plain
  # kickstart (a no-op on a running unit).
  refreshFn = ''
    get_pid() { /bin/launchctl print "$1" 2>/dev/null | awk '/^[[:space:]]*pid = /{print $3; exit}'; }
    refresh_unit() {
      target="$1"
      old_pid=$(get_pid "$target")
      /bin/launchctl kill TERM "$target" 2>>"$log_file" || true
      i=0
      while [ "$i" -lt 15 ]; do
        cur=$(get_pid "$target")
        [ -z "$cur" ] || [ "$cur" != "$old_pid" ] && break
        sleep 1
        i=$((i + 1))
      done
      cur=$(get_pid "$target")
      if [ -n "$cur" ] && [ "$cur" = "$old_pid" ]; then
        /bin/launchctl kickstart -k "$target" 2>>"$log_file" || true
        log "forced kickstart $target (ignored TERM)"
      elif [ -z "$cur" ]; then
        /bin/launchctl kickstart "$target" 2>>"$log_file" || true
        log "restarted $target"
      else
        log "restarted $target (graceful, pid $old_pid -> $cur)"
      fi
    }
  '';

  userRefresh = pkgs.writeShellScript "service-refresh-user" ''
    set -u
    stamp_dir="$HOME/Library/Application Support/service-refresh"
    log_file="$HOME/Library/Logs/service-refresh.log"
    mkdir -p "$stamp_dir" "$(dirname "$log_file")"
    log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >>"$log_file"; }
    ${refreshFn}
    now=$(date +%s)
    uid=$(id -u)
    for label in ${toString orderedAgentLabels}; do
      stamp="$stamp_dir/$label"
      last=0
      [ -f "$stamp" ] && last=$(cat "$stamp")
      if [ $((now - last)) -lt $((${toString maxAgeHours} * 3600)) ]; then
        log "skip $label (age $((now - last))s < ${toString maxAgeHours}h)"
        continue
      fi
      refresh_unit "gui/$uid/$label"
      date +%s >"$stamp"
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

  # The Tailscale.app network extension is NOT in this list and is never
  # touched: its lifecycle belongs to the app. Only nix-declared daemons
  # (com.tailscale.tailscaled, determinate-nixd, ...) are covered.
  systemRefresh = pkgs.writeShellScript "service-refresh-system" ''
    set -u
    stamp_dir="/var/lib/service-refresh"
    log_file="/Library/Logs/service-refresh-system.log"
    mkdir -p "$stamp_dir"
    log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >>"$log_file"; }
    ${refreshFn}
    now=$(date +%s)
    for label in ${toString daemonLabels}; do
      stamp="$stamp_dir/$label"
      last=0
      [ -f "$stamp" ] && last=$(cat "$stamp")
      if [ $((now - last)) -lt $((${toString maxAgeHours} * 3600)) ]; then
        log "skip $label (age $((now - last))s < ${toString maxAgeHours}h)"
        continue
      fi
      refresh_unit "system/$label"
      date +%s >"$stamp"
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
