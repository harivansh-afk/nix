# spark-display: one switch for casting the mac onto spark's monitor.
#
#   on      raise the cast (and keep it healthy until told otherwise)
#   off     tear the cast down (monitor returns to spark's console)
#   status  one-line state of every piece
#
# `on` does not run the machinery directly: it flips a state file and kicks
# the org.nixos.spark-cast launchd agent, which runs `supervise` - a
# convergence loop that every 5s makes reality match the desired state:
# DeskPad running -> virtual display at native res -> Sunshine capturing the
# *current* display id -> kiosk running on spark. Any piece dying (DeskPad
# closed by hand, Sunshine crash, kiosk stop) is re-raised within one tick.
# CGDirectDisplayIDs re-roll on every DeskPad relaunch and resolution change,
# which silently pointed Sunshine at the built-in screen twice on setup
# night; the loop resyncs sunshine.conf from displayplacer's contextual id
# (verified equal to the id Sunshine logs) whenever it drifts.
#
# The resolution is only applied when wrong (applying it re-rolls the id),
# and the arrangement origin is only set in that same rare branch, so a
# manual rearrange in System Settings sticks.
#
# spark side needs no supervision: the kiosk unit's moonlight loop retries
# every 3s on its own, and the polkit rule on spark scopes this user to
# start/stop of exactly cage-tty1.service (no sudo over ssh).

DP=/opt/homebrew/bin/displayplacer
STATE_DIR="$HOME/.local/state/spark-cast"
ON_FILE="$STATE_DIR/on"
STATUS_FILE="$STATE_DIR/status"
SUNSHINE_CONF="$HOME/.config/sunshine/sunshine.conf"
APP="/Applications/DeskPad.app"
CAST_LABEL="org.nixos.spark-cast"
SUNSHINE_LABEL="org.nixos.sunshine"
RES="3440x1440"
HZ="60"
ORIGIN="(-573,-1440)"

usage() {
  echo "usage: spark-display on|off|status" >&2
  exit 64
}

spark_ctl() {
  ssh -o ConnectTimeout=5 -o BatchMode=yes spark "$@"
}

note() {
  printf '%s\n' "$1" >"$STATUS_FILE"
}

# One line per virtual (non-builtin) display: "<persistent> <contextual> <res>"
virtual_info() {
  "$DP" list | awk '
    /^Persistent screen id:/ { pid = $4 }
    /^Contextual screen id:/ { ctx = $4 }
    /^Type:/ { builtin = ($0 ~ /MacBook built in/) }
    /^Resolution:/ { if (!builtin && pid != "") { print pid, ctx, $2 }; pid = "" }
  '
}

converge() {
  if ! /usr/bin/pgrep -xq DeskPad; then
    /usr/bin/open "$APP" 2>/dev/null || true
    note "launching deskpad"
    return 0
  fi

  local info pid ctx res
  info=$(virtual_info | head -1)
  if [ -z "$info" ]; then
    note "waiting for virtual display"
    return 0
  fi
  read -r pid ctx res <<<"$info"

  if [ "$res" != "$RES" ]; then
    "$DP" "id:$pid res:$RES hz:$HZ enabled:true scaling:off origin:$ORIGIN degree:0" >/dev/null 2>&1 || true
    note "setting resolution to $RES"
    return 0
  fi

  local want
  want=$(printf 'min_log_level = info\noutput_name = %s' "$ctx")
  if [ "$(cat "$SUNSHINE_CONF" 2>/dev/null)" != "$want" ]; then
    printf '%s\n' "$want" >"$SUNSHINE_CONF"
    /bin/launchctl kickstart -k "gui/$(id -u)/$SUNSHINE_LABEL" 2>/dev/null || true
    note "pointing sunshine at display $ctx"
    return 0
  fi

  if ! /usr/bin/nc -z 127.0.0.1 47989 >/dev/null 2>&1; then
    /bin/launchctl kickstart -k "gui/$(id -u)/$SUNSHINE_LABEL" 2>/dev/null || true
    note "restarting sunshine"
    return 0
  fi

  # Publish this mac's LAN IP so the kiosk can stream LAN-direct (mDNS is
  # blocked on the office network); the kiosk falls back to tailscale when
  # the published IP is unreachable, so a stale value only costs a retry.
  local lan cur
  lan=$(/usr/sbin/ipconfig getifaddr en0 2>/dev/null || true)
  if [ -n "$lan" ]; then
    cur=$(spark_ctl cat /var/lib/spark-cast/host 2>/dev/null || true)
    if [ "$cur" != "$lan" ]; then
      spark_ctl "printf '%s' '$lan' > /var/lib/spark-cast/host" 2>/dev/null || true
      note "publishing lan ip $lan"
      return 0
    fi
  fi

  local kiosk
  kiosk=$(spark_ctl systemctl is-active cage-tty1.service 2>/dev/null || true)
  if [ "$kiosk" != "active" ]; then
    spark_ctl systemctl start cage-tty1.service 2>/dev/null || true
    note "starting kiosk on spark"
    return 0
  fi

  note "streaming (display $ctx)"
}

teardown() {
  spark_ctl systemctl stop cage-tty1.service 2>/dev/null || true
  /usr/bin/osascript -e 'quit app "DeskPad"' >/dev/null 2>&1 || true
  note "off"
}

[ $# -eq 1 ] || usage

case "$1" in
on)
  mkdir -p "$STATE_DIR"
  touch "$ON_FILE"
  /bin/launchctl kickstart "gui/$(id -u)/$CAST_LABEL" 2>/dev/null || true
  echo "cast: on (converging; check spark-display status)"
  ;;
off)
  mkdir -p "$STATE_DIR"
  rm -f "$ON_FILE"
  teardown
  echo "cast: off (monitor back to spark console)"
  ;;
status)
  if [ -f "$ON_FILE" ]; then echo "cast: on"; else echo "cast: off"; fi
  echo "state: $(cat "$STATUS_FILE" 2>/dev/null || echo unknown)"
  if /usr/bin/pgrep -xq DeskPad; then echo "deskpad: running"; else echo "deskpad: stopped"; fi
  if /usr/bin/nc -z 127.0.0.1 47989 >/dev/null 2>&1; then echo "sunshine: listening"; else echo "sunshine: down"; fi
  echo "kiosk: $(spark_ctl systemctl is-active cage-tty1.service 2>/dev/null || echo unreachable)"
  ;;
supervise)
  mkdir -p "$STATE_DIR"
  while [ -f "$ON_FILE" ]; do
    converge
    sleep 5
  done
  teardown
  ;;
*)
  usage
  ;;
esac
