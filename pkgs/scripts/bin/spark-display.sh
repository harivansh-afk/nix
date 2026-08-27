# spark-display on|off|status: cast the mac onto spark's monitor.
# `on` flips a state file; the org.nixos.spark-cast agent runs `supervise`,
# a convergence loop over DeskPad -> resolution -> published LAN IP ->
# spark kiosk -> sunshine display id. Each fix waits (bounded) for its own
# postcondition and the loop re-runs almost immediately after acting, so a
# cold start walks the whole ladder in a few seconds; the 5s tick only
# maintains steady state. The kiosk starts before sunshine on purpose:
# the panel's HDMI wake and moonlight's retry loop overlap sunshine
# bring-up (safe: the gate keeps sunshine down until its conf holds the
# fresh display id, so an early kiosk sees connection-refused, never a
# wrong display). See AGENTS.md "Casting".

DP=/opt/homebrew/bin/displayplacer
STATE_DIR="$HOME/.local/state/spark-cast"
ON_FILE="$STATE_DIR/on"
STATUS_FILE="$STATE_DIR/status"
UUID_FILE="$STATE_DIR/display-uuid"
SUNSHINE_GATE="$STATE_DIR/sunshine-on"
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

# await <seconds> <cmd...>: poll until cmd succeeds or the deadline passes.
# Fix branches use this to wait for their own postcondition, which is what
# makes fast re-runs safe: without it, a quick next pass would see e.g.
# sunshine's port not yet bound and kickstart -k it mid-start, forever.
await() {
  local deadline=$((SECONDS + $1))
  shift
  until "$@" >/dev/null 2>&1; do
    [ "$SECONDS" -lt "$deadline" ] || return 1
    sleep 0.3
  done
}

deskpad_present() {
  [ -n "$(deskpad_display)" ]
}

deskpad_at_res() {
  [ "$(deskpad_display | awk '{ print $3 }')" = "$RES" ]
}

sunshine_listening() {
  /usr/bin/nc -z 127.0.0.1 47989
}

# Sunshine on a stale/invalid output_name silently falls back to capturing
# the real desktop (CGMainDisplayID), so it only runs while the display id
# in its conf is trustworthy. The gate file backs the launchd KeepAlive
# PathState: down = kill and stay dead, up = start and restart on crash.
sunshine_down() {
  rm -f "$SUNSHINE_GATE"
  /bin/launchctl kill SIGTERM "gui/$(id -u)/$SUNSHINE_LABEL" 2>/dev/null || true
}

sunshine_up() {
  touch "$SUNSHINE_GATE"
  /bin/launchctl kickstart -k "gui/$(id -u)/$SUNSHINE_LABEL" 2>/dev/null || true
}

# One line per non-builtin display: "<persistent-uuid> <contextual-id> <res> <serial>"
displays() {
  "$DP" list | awk '
    /^Persistent screen id:/ { pid = $4 }
    /^Contextual screen id:/ { ctx = $4 }
    /^Serial screen id:/ { ser = $4 }
    /^Type:/ { builtin = ($0 ~ /MacBook built in/) }
    /^Resolution:/ { if (!builtin && pid != "") { print pid, ctx, $2, ser }; pid = "" }
  '
}

# DeskPad only, never a real monitor: pin its persistent UUID on first
# sight (DeskPad reports serial s1) and match on the pin from then on.
deskpad_display() {
  local all line
  all=$(displays)
  [ -n "$all" ] || return 0
  if [ -f "$UUID_FILE" ]; then
    line=$(awk -v u="$(cat "$UUID_FILE")" '$1 == u' <<<"$all" | head -1)
    if [ -n "$line" ]; then
      printf '%s\n' "$line"
      return 0
    fi
  fi
  line=$(awk '$4 == "s1"' <<<"$all" | head -1)
  if [ -n "$line" ]; then
    awk '{print $1}' <<<"$line" >"$UUID_FILE"
    printf '%s\n' "$line"
  fi
}

# One fix per pass, ACTED=1 when something was done; supervise re-runs
# almost immediately after an action and sleeps 5s only when steady.
converge() {
  ACTED=0

  if ! /usr/bin/pgrep -xq DeskPad; then
    ACTED=1
    sunshine_down
    # -gj: launch hidden and in the background; the virtual display does
    # not need a visible window, and the preview is patched out anyway.
    /usr/bin/open -gj "$APP" 2>/dev/null || true
    note "launching deskpad"
    await 12 deskpad_present || true
    return 0
  fi

  local line pid ctx res
  line=$(deskpad_display)
  if [ -z "$line" ]; then
    ACTED=1
    sunshine_down
    note "waiting for virtual display"
    await 8 deskpad_present || true
    return 0
  fi
  read -r pid ctx res _ <<<"$line"

  # Setting the resolution re-rolls the display id, so only when wrong,
  # and never with sunshine still serving the id about to die.
  if [ "$res" != "$RES" ]; then
    ACTED=1
    sunshine_down
    "$DP" "id:$pid res:$RES hz:$HZ enabled:true scaling:off origin:$ORIGIN degree:0" >/dev/null 2>&1 || true
    note "setting resolution to $RES"
    await 6 deskpad_at_res || true
    return 0
  fi

  # The two spark-side steps run before sunshine: the kiosk tolerates a
  # down sunshine (connection refused, fast retry), so the panel wake and
  # moonlight's connect loop overlap sunshine bring-up instead of
  # serializing after it.
  local lan cur
  lan=$(/usr/sbin/ipconfig getifaddr en0 2>/dev/null || true)
  if [ -n "$lan" ]; then
    cur=$(spark_ctl cat /var/lib/spark-cast/host 2>/dev/null || true)
    if [ "$cur" != "$lan" ]; then
      ACTED=1
      printf '%s' "$lan" | spark_ctl "cat > /var/lib/spark-cast/host" 2>/dev/null || true
      note "publishing lan ip $lan"
      return 0
    fi
  fi

  local kiosk
  kiosk=$(spark_ctl systemctl is-active cage-tty1.service 2>/dev/null || true)
  if [ "$kiosk" != "active" ]; then
    ACTED=1
    spark_ctl systemctl start cage-tty1.service 2>/dev/null || true
    note "starting kiosk on spark"
    return 0
  fi

  # Input stays on the mac: disabling all client input keeps sunshine's
  # virtual HID machinery out of the event path (HID stalls froze the mac).
  # lan_encryption_mode 2: video RTP is cleartext by default (sunshine's
  # lan default never even advertises video encryption support); mandatory
  # is safe because the only client is our kiosk, which always opts in to
  # ENCFLG_ALL on AES-capable hardware. origin_web_ui_allowed pc: the web
  # UI answers localhost only (pairing approval runs on the mac anyway).
  local want
  want=$(printf 'min_log_level = info\nkeyboard = disabled\nmouse = disabled\ncontroller = disabled\noutput_name = %s\nlan_encryption_mode = 2\norigin_web_ui_allowed = pc' "$ctx")
  if [ "$(cat "$SUNSHINE_CONF" 2>/dev/null)" != "$want" ]; then
    ACTED=1
    printf '%s\n' "$want" >"$SUNSHINE_CONF"
    sunshine_up
    note "pointing sunshine at display $ctx"
    await 8 sunshine_listening || true
    return 0
  fi

  if ! sunshine_listening >/dev/null 2>&1; then
    ACTED=1
    sunshine_up
    note "restarting sunshine"
    await 8 sunshine_listening || true
    return 0
  fi

  note "streaming (display $ctx)"
}

teardown() {
  spark_ctl systemctl stop cage-tty1.service 2>/dev/null || true
  sunshine_down
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
  echo "cast: off (monitor going dark)"
  ;;
status)
  if [ -f "$ON_FILE" ]; then echo "cast: on"; else echo "cast: off"; fi
  echo "state: $(cat "$STATUS_FILE" 2>/dev/null || echo unknown)"
  if /usr/bin/pgrep -xq DeskPad; then echo "deskpad: running"; else echo "deskpad: stopped"; fi
  if /usr/bin/nc -z 127.0.0.1 47989 >/dev/null 2>&1; then echo "sunshine: listening"; else echo "sunshine: down"; fi
  kiosk=$(spark_ctl systemctl is-active cage-tty1.service 2>/dev/null || true)
  echo "kiosk: ${kiosk:-unreachable}"
  monitor=$(spark_ctl cat /sys/class/drm/card1-HDMI-A-1/enabled 2>/dev/null || true)
  echo "monitor: ${monitor:-unknown}"
  ;;
supervise)
  mkdir -p "$STATE_DIR"
  while [ -f "$ON_FILE" ]; do
    converge
    if [ "$ACTED" = 1 ]; then sleep 0.3; else sleep 5; fi
  done
  teardown
  ;;
*)
  usage
  ;;
esac
