# The shell a Rex pane runs on the Mac (dots/zsh/zshrc runs it inside Rex).
# Attaches the pane to a muxd pty on @HOST@ named after the Rex block, so a
# reopened pane finds its own shell; adopts an orphaned rex-* pty when the
# block has none; falls back to a local login shell when @HOST@ is away.
# REX_LOCAL=1 on the fallback keeps zshrc from re-entering this script.
# The relay mirrors the pty's foreground program in its own process name
# (`claude` while claude runs there, `zsh` at the prompt), which is what
# Rex reads for the pane's program status, icon and clear behaviour.

host="@HOST@"
block="${REX_BLOCK:-}"

local_shell() {
  echo "rex-spark: $1; starting a local shell" >&2
  REX_LOCAL=1 exec "${SHELL:-/bin/zsh}" -l
}

[ -n "$block" ] || local_shell "REX_BLOCK is unset, not a Rex pane"
command -v mux-attach >/dev/null || local_shell "mux-attach is not on PATH"

listing="$(muxd ls "$host" 2>/dev/null)" || local_shell "$host is unreachable"

target="rex-$block"
flags=()
if printf '%s\n' "$listing" | jq -e --arg n "$target" 'select(.name == $n and .exited == false)' >/dev/null 2>&1; then
  flags+=(--expect-existing)
else
  orphan="$(printf '%s\n' "$listing" | jq -r 'select((.name | startswith("rex-")) and .attached == false and .exited == false) | .name' | head -n 1)"
  if [ -n "$orphan" ]; then
    target="$orphan"
    flags+=(--expect-existing)
  fi
fi

export TERM=xterm-ghostty
exec mux-attach "$host:$target" --mirror-foreground "${flags[@]}"
