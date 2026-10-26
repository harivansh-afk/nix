host="@HOST@"
block="${REX_BLOCK:-}"

local_shell() {
  echo "rex-spark: $1; starting a local shell" >&2
  REX_LOCAL=1 exec "${SHELL:-/bin/zsh}" -l
}

[ -n "$block" ] || local_shell "REX_BLOCK is unset, not a Rex pane"
ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" true 2>/dev/null || local_shell "$host is unreachable"

session="rex-$block"
remote="exec zmx attach $session"
if [ -n "${REX_CWD:-}" ]; then
  printf -v dir '%q' "$REX_CWD"
  remote="cd $dir 2>/dev/null; $remote"
fi

export TERM=xterm-ghostty
while :; do
  ssh -t "$host" "$remote" && status=0 || status=$?
  if [ "$status" -eq 255 ]; then
    echo "rex-spark: lost $host; reconnecting" >&2
    sleep 1
    continue
  fi
  # Reattach after a detach (ctrl+\) while the session lives.
  ssh "$host" zmx list --short 2>/dev/null | grep -qxF "$session" || exit "$status"
done
