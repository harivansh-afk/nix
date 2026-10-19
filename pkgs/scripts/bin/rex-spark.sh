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
elif [ -n "${REX_PARENT:-}" ]; then
  flags+=(--cwd-from "rex-$REX_PARENT")
fi

export TERM=xterm-ghostty
exec mux-attach "$host:$target" --mirror-foreground "${flags[@]}"
