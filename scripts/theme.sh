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
  local tmux_target

  case "$mode" in
    dark)
      tmux_target="@TMUX_DARK_FILE@"
      ;;
    light)
      tmux_target="@TMUX_LIGHT_FILE@"
      ;;
    *)
      echo "invalid mode: $mode" >&2
      exit 1
      ;;
  esac

  mkdir -p "@STATE_DIR@" "@TMUX_DIR@"
  printf '%s\n' "$mode" > "@STATE_FILE@"
  ln -sfn "$tmux_target" "@TMUX_CURRENT_FILE@"

  if command -v tmux >/dev/null 2>&1 && tmux start-server >/dev/null 2>&1; then
    tmux source-file "@TMUX_CONFIG@" >/dev/null 2>&1 || true
  fi

  for socket in /tmp/nvim-*.sock; do
    [[ -S "$socket" ]] || continue
    nvim --server "$socket" --remote-send "<Cmd>ThemeSync $mode<CR>" >/dev/null 2>&1 || true
  done
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
