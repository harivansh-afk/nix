usage() {
  echo "usage: theme <dark|light|toggle|current>"
}

read_mode() {
  if [[ -f "@STATE_FILE@" ]]; then
    mode=$(tr -d '[:space:]' < "@STATE_FILE@")
    if [[ "$mode" == "dark" || "$mode" == "light" ]]; then
      echo "$mode"
      return
    fi
  fi

  echo "@DEFAULT_MODE@"
}

link_mode_assets() {
  local mode="$1"
  local ghostty_target
  local tmux_target
  local apple_dark_mode

  case "$mode" in
    dark)
      ghostty_target="@GHOSTTY_DARK_FILE@"
      tmux_target="@TMUX_DARK_FILE@"
      apple_dark_mode=true
      ;;
    light)
      ghostty_target="@GHOSTTY_LIGHT_FILE@"
      tmux_target="@TMUX_LIGHT_FILE@"
      apple_dark_mode=false
      ;;
    *)
      echo "invalid mode: $mode" >&2
      exit 1
      ;;
  esac

  mkdir -p "@STATE_DIR@" "@GHOSTTY_DIR@" "@TMUX_DIR@"
  printf '%s\n' "$mode" > "@STATE_FILE@"
  ln -sfn "$ghostty_target" "@GHOSTTY_CURRENT_FILE@"
  ln -sfn "$tmux_target" "@TMUX_CURRENT_FILE@"

  if command -v tmux >/dev/null 2>&1 && tmux start-server >/dev/null 2>&1; then
    tmux source-file "@TMUX_CONFIG@" >/dev/null 2>&1 || true
  fi

  if [[ "$(uname -s)" == "Darwin" ]] && command -v osascript >/dev/null 2>&1; then
    osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to ${apple_dark_mode}" >/dev/null 2>&1 || true

    osascript <<'EOF' >/dev/null 2>&1 || true
tell application "System Events"
  if not (exists process "Ghostty") then
    return
  end if

  tell process "Ghostty"
    click menu item "Reload Configuration" of menu 1 of menu bar item "Ghostty" of menu bar 1
  end tell
end tell
EOF
  fi

  while IFS= read -r socket; do
    [[ -S "$socket" ]] || continue
    nvim --server "$socket" --remote-expr "execute('ThemeSync $mode')" >/dev/null 2>&1 || true
  done < <(
    {
      find /tmp -maxdepth 1 -type s -name 'nvim-*.sock' 2>/dev/null
      find "${TMPDIR:-/tmp}" -type s -path "*/nvim.${USER}/*/nvim.*" 2>/dev/null
    } | sort -u
  )
}

mode="${1:-current}"

case "$mode" in
  dark|light)
    ;;
  toggle)
    if [[ "$(read_mode)" == "dark" ]]; then
      mode="light"
    else
      mode="dark"
    fi
    ;;
  current)
    read_mode
    exit 0
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac

link_mode_assets "$mode"
printf 'applied %s theme\n' "$mode"
