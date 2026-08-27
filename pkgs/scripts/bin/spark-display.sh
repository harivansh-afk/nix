# Toggle spark's HDMI monitor as an extended display for this mac.
# on:  open DeskPad (the virtual display Sunshine captures), then start the
#      moonlight kiosk on spark; it connects within a few seconds.
# off: stop the kiosk (monitor returns to the console), quit DeskPad so the
#      virtual display cannot trap windows or wedge macOS sleep.
# The systemctl calls need no sudo: a polkit rule on spark scopes unit
# start/stop of cage-tty1.service to this user (hosts/spark/services/moonlight.nix).

usage() {
  echo "usage: spark-display on|off|status" >&2
  exit 64
}

[ $# -eq 1 ] || usage

spark_ctl() {
  ssh -o ConnectTimeout=5 -o BatchMode=yes spark "$@"
}

case "$1" in
  on)
    /usr/bin/open -a DeskPad
    spark_ctl systemctl start cage-tty1.service
    echo "casting: DeskPad display -> spark monitor"
    ;;
  off)
    spark_ctl systemctl stop cage-tty1.service
    /usr/bin/osascript -e 'tell application "DeskPad" to quit' >/dev/null 2>&1 || true
    echo "cast stopped: monitor back to console"
    ;;
  status)
    echo "kiosk: $(spark_ctl systemctl is-active cage-tty1.service || true)"
    if /usr/bin/pgrep -xq DeskPad; then
      echo "deskpad: running"
    else
      echo "deskpad: stopped"
    fi
    ;;
  *)
    usage
    ;;
esac
