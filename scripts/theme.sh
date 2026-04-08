usage() {
  echo "usage: theme <dark|light|toggle|current|gen>"
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

@THEME_ASSETS_TEXT@

set_wallpaper() {
  if [[ "$(uname -s)" == "Darwin" ]] && command -v osascript >/dev/null 2>&1; then
    if [[ -f "@WALLPAPER_CURRENT_FILE@" ]]; then
      wp_resolved=$(readlink -f "@WALLPAPER_CURRENT_FILE@" 2>/dev/null || echo "@WALLPAPER_CURRENT_FILE@")
      # macOS caches wallpaper data by file path - copy to a unique temp path
      # so macOS is forced to read the new image data
      wp_dir=$(dirname "$wp_resolved")
      wp_tmp="${wp_dir}/.wallpaper-active-$$.jpg"
      rm -f "${wp_dir}"/.wallpaper-active-*.jpg 2>/dev/null || true
      cp "$wp_resolved" "$wp_tmp"
      osascript -e "tell application \"System Events\" to tell every desktop to set picture to \"${wp_tmp}\"" >/dev/null 2>&1 || true
    fi
  fi
}

link_mode_assets() {
  local mode="$1"
  theme_load_mode_assets "$mode"
  mode="$THEME_MODE"

  mkdir -p "@STATE_DIR@" "@FZF_DIR@" "@GHOSTTY_DIR@" "@TMUX_DIR@" "@LAZYGIT_DIR@" "@WALLPAPER_DIR@"
  printf '%s\n' "$mode" > "@STATE_FILE@"
  ln -sfn "$THEME_FZF_TARGET" "@FZF_CURRENT_FILE@"
  ln -sfn "$THEME_GHOSTTY_TARGET" "@GHOSTTY_CURRENT_FILE@"
  ln -sfn "$THEME_TMUX_TARGET" "@TMUX_CURRENT_FILE@"
  ln -sfn "$THEME_LAZYGIT_TARGET" "@LAZYGIT_CURRENT_FILE@"

  if [[ -f "$THEME_WALLPAPER" ]]; then
    ln -sfn "$THEME_WALLPAPER" "@WALLPAPER_CURRENT_FILE@"
  fi

  if command -v tmux >/dev/null 2>&1 && tmux start-server >/dev/null 2>&1; then
    tmux source-file "@TMUX_CONFIG@" >/dev/null 2>&1 || true
  fi

  if [[ "$(uname -s)" == "Darwin" ]] && command -v osascript >/dev/null 2>&1; then
    mkdir -p "@LAZYGIT_DARWIN_DIR@"
    ln -sfn "$THEME_DARWIN_LAZYGIT_TARGET" "@LAZYGIT_DARWIN_FILE@"

    osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to ${THEME_APPLE_DARK_MODE}" >/dev/null 2>&1 || true

    set_wallpaper

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
  gen)
    wallpaper-gen
    set_wallpaper
    printf 'generated new wallpaper\n'
    exit 0
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac

link_mode_assets "$mode"
printf 'applied %s theme\n' "$mode"
