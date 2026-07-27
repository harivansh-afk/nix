# fork: spawn a forked copy of an agent session in a sibling herdr pane.
# herdr already tracks the session identity of every agent pane (the
# integration hooks report it for native restore), so this works from any
# context that knows the pane: `!fork` inside claude, a shell in the pane,
# or `fork <pane-id>` from anywhere in the session.
#
#   fork                     fork the agent in the current pane
#   fork <pane-id>           fork the agent in pane <pane-id> (e.g. w1:p2)
#   fork [pane-id] <prompt>  fork, then submit <prompt> to the copy
#   fork --no-focus ...      keep focus on the calling pane
#
# Fork semantics per harness:
#   claude  claude --resume <id> --fork-session  (native: new session id)
#   codex   codex fork <id>                      (native fork subcommand)
#   omp     copy session file under a fresh id, omp --resume <copy-path>
#           (omp --resume APPENDS to the parent's file - verified - so the
#           copy is what makes it a fork instead of a concurrent writer)

set -euo pipefail

die() {
  printf 'fork: %s\n' "$1" >&2
  exit 1
}

usage() {
  cat <<'EOF'
fork: spawn a forked copy of an agent session in a sibling herdr pane

  fork                     fork the agent in the current pane
  fork <pane-id>           fork the agent in pane <pane-id> (e.g. w1:p2)
  fork [pane-id] <prompt>  fork, then submit <prompt> to the copy
  fork --no-focus ...      keep focus on the calling pane

Supported agents: claude, codex, omp
EOF
}

[ "${HERDR_ENV:-}" = 1 ] || die "not inside a herdr session (HERDR_ENV unset)"

focus=1
target="${HERDR_PANE_ID:-}"
prompt=""
target_set=0

for arg in "$@"; do
  case "$arg" in
  --no-focus) focus=0 ;;
  -h | --help)
    usage
    exit 0
    ;;
  -*) die "unknown flag: $arg (see fork --help)" ;;
  *)
    # First bare arg that looks like a pane id targets that pane;
    # everything else accumulates into the initial prompt.
    if [ "$target_set" = 0 ] && [ -z "$prompt" ] &&
      printf '%s' "$arg" | grep -Eq '^w[A-Za-z0-9]+:p[A-Za-z0-9]+$'; then
      target="$arg"
      target_set=1
    else
      prompt="${prompt:+$prompt }$arg"
    fi
    ;;
  esac
done

[ -n "$target" ] || die "no target pane (HERDR_PANE_ID unset; pass a pane id)"

# --- Resolve the agent occupying the target pane -----------------------------
agent_json="$(herdr agent get "$target" 2>/dev/null)" ||
  die "no agent detected in pane $target"

kind="$(jq -r '.result.agent.agent // empty' <<<"$agent_json")"
sess_kind="$(jq -r '.result.agent.agent_session.kind // empty' <<<"$agent_json")"
sess_value="$(jq -r '.result.agent.agent_session.value // empty' <<<"$agent_json")"
cwd="$(jq -r '.result.agent.foreground_cwd // .result.agent.cwd // empty' <<<"$agent_json")"

[ -n "$kind" ] || die "pane $target has no recognized agent"
[ -n "$sess_value" ] || die "herdr has no session identity for the $kind in $target (integration installed?)"

resume_args=()
case "$kind" in
claude)
  [ "$sess_kind" = id ] || die "expected a claude session id, got $sess_kind"
  resume_args=(--resume "$sess_value" --fork-session)
  ;;
codex)
  [ "$sess_kind" = id ] || die "expected a codex session id, got $sess_kind"
  resume_args=(fork "$sess_value")
  ;;
omp)
  # omp --resume appends to the resumed file in place (no new file), so a
  # plain resume of a live session would race the parent on one jsonl.
  # Fork = copy the session file under a fresh id, resume the copy by path.
  if [ "$sess_kind" = path ]; then
    src="$sess_value"
  else
    src="$(grep -rl --include='*.jsonl' -m1 "\"id\":\"$sess_value\"" \
      "$HOME/.omp/agent/sessions" 2>/dev/null | head -1)"
  fi
  [ -n "$src" ] && [ -f "$src" ] || die "cannot locate omp session file for $sess_value"
  new_id="$(uuidgen | tr '[:upper:]' '[:lower:]')"
  dst="$(dirname "$src")/$(date -u +%Y-%m-%dT%H-%M-%S-000Z)_${new_id}.jsonl"
  jq -c --arg id "$new_id" 'if .type == "session" then .id = $id else . end' \
    "$src" >"$dst"
  resume_args=(--resume "$dst")
  ;;
*)
  die "unsupported agent kind: $kind (supported: claude, codex, omp)"
  ;;
esac

# --- Split a sibling pane in the same tab ------------------------------------
# Terminal cells are ~2:1 tall, so a pane wider than 2x its height splits
# right; otherwise down.
rect="$(herdr pane layout --pane "$target" |
  jq -r --arg p "$target" '.result.layout.panes[] | select(.pane_id == $p) | "\(.rect.width) \(.rect.height)"')"
read -r width height <<<"${rect:-0 0}"
direction=down
[ "$width" -ge $((height * 2)) ] && direction=right

split_args=(--pane "$target" --direction "$direction")
[ -n "$cwd" ] && split_args+=(--cwd "$cwd")
[ "$focus" = 1 ] && split_args+=(--focus)

new_pane="$(herdr pane split "${split_args[@]}" | jq -r '.result.pane.pane_id // empty')"
[ -n "$new_pane" ] || die "pane split failed"

# --- Start the forked agent --------------------------------------------------
# Unique live-agent name: fork, fork-2, fork-3, ...
names="$(herdr agent list | jq -r '.result.agents[].name // empty')"
name=fork
n=1
while grep -qxF "$name" <<<"$names"; do
  n=$((n + 1))
  name="fork-$n"
done

# The fresh pane's shell needs a beat to reach its interactive prompt;
# herdr rejects agent start with agent_pane_busy until then. Retry briefly,
# and close the split instead of leaving an orphan pane if the start fails.
tries=0
while :; do
  if out="$(herdr agent start "$name" --kind "$kind" --pane "$new_pane" -- "${resume_args[@]}" 2>&1)"; then
    break
  fi
  tries=$((tries + 1))
  if [ "$tries" -ge 20 ] || ! grep -q agent_pane_busy <<<"$out"; then
    herdr pane close "$new_pane" >/dev/null 2>&1 || true
    die "failed to start $kind fork in $new_pane: $out"
  fi
  sleep 0.5
done

if [ -n "$prompt" ]; then
  # A fresh claude launch with permissions.defaultMode=bypassPermissions
  # shows the bypass disclaimer (never persisted; accept it by hand). herdr
  # classifies that dialog as idle, so a submitted prompt would land on
  # "No, exit" - skip auto-submission while the dialog is up.
  sleep 1
  if herdr pane read "$new_pane" 2>/dev/null | grep -q 'Yes, I accept'; then
    printf 'fork: %s is waiting on the bypass dialog; prompt NOT submitted:\n  %s\n' \
      "$new_pane" "$prompt" >&2
  else
    herdr agent wait "$name" --until idle --timeout 30000 >/dev/null 2>&1 ||
      die "fork started in $new_pane but never went idle; prompt not submitted"
    herdr agent prompt "$name" "$prompt" >/dev/null
  fi
fi

printf 'forked %s (%s) -> pane %s as %s\n' "$kind" "$sess_value" "$new_pane" "$name"
