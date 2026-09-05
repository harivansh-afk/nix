set -eu

for _attempt in $(seq 1 30); do
  desktop_env=$(systemctl --user show-environment)
  wayland_display=$(printf '%s\n' "$desktop_env" | sed -n 's/^WAYLAND_DISPLAY=//p')
  if [ -n "$wayland_display" ] && [ -S "$XDG_RUNTIME_DIR/$wayland_display" ]; then
    target="$HERMES_HOME/desktop.env"
    tmp=$(mktemp "$target.XXXXXX")
    trap 'rm -f "$tmp"' EXIT
    printf '%s\n' "$desktop_env" | sed -n '/^WAYLAND_DISPLAY=/p; /^SWAYSOCK=/p' >"$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$target"
    exit 0
  fi
  sleep 1
done

echo "Spark's Sway session is not ready" >&2
exit 1
