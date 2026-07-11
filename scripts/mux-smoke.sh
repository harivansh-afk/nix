#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MUX_SOURCE="$REPO_ROOT/scripts/bin/mux.sh"
work="$(mktemp -d)"
server_pid=""

cleanup() {
  if [ -n "$server_pid" ]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -rf "$work"
}
trap cleanup EXIT

fail() {
  printf 'mux smoke: %s\n' "$1" >&2
  exit 1
}

parent="$work/repo"
child="$parent/.worktrees/task"
state_home="$work/state"
sessions="$state_home/nvim/mux/sessions"
runtime="$work/runtime"
bin="$work/bin"
orphan="$work/deleted-project"
mkdir -p "$parent/.git" "$child/.git" "$sessions" "$runtime/mux" "$bin"
printf '%s\n' "$child" >"$sessions/task.root"
printf 'session\n' >"$sessions/task.vim"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  "printf '%s\\n' \"\$MUX_TEST_PARENT\" \"\$MUX_TEST_CHILD\"" \
  >"$bin/zoxide"
chmod +x "$bin/zoxide"

output="$(
  PATH="$bin:$PATH" \
    HOME="$work/home" \
    XDG_STATE_HOME="$state_home" \
    XDG_RUNTIME_DIR="$runtime" \
    MUX_NVIM=true \
    MUX_TEST_PARENT="$parent" \
    MUX_TEST_CHILD="$child" \
    bash "$MUX_SOURCE" list
)"
expected="$(printf '%s\t\t%s' "$child" dir)"
printf '%s\n' "$output" | grep -Fxq "$expected" || fail "saved nested project was pruned from mux list"

printf '%s\n' "$orphan" >"$sessions/orphan.root"
printf 'session\n' >"$sessions/orphan.vim"
printf 'restore\n' >"$sessions/orphan.restore"
PATH="$bin:$PATH" \
  HOME="$work/home" \
  XDG_STATE_HOME="$state_home" \
  XDG_RUNTIME_DIR="$runtime" \
  MUX_NVIM=true \
  bash "$MUX_SOURCE" clean
[ -f "$sessions/task.root" ] && [ -f "$sessions/task.vim" ] || fail "clean removed a valid saved session"
[ ! -e "$sessions/orphan.root" ] || fail "clean kept an orphan root sidecar"
[ ! -e "$sessions/orphan.vim" ] || fail "clean kept an orphan snapshot"
[ ! -e "$sessions/orphan.restore" ] || fail "clean kept an orphan restore marker"

root="$work/p"
runtime="$work/r"
bin="$work/b"
mkdir -p "$root/.git" "$runtime/mux" "$bin"
root="$(realpath "$root")"
runtime="$(realpath "$runtime")"
base="$(basename "$root" | tr -c 'A-Za-z0-9._-' '_')"
hash="$(printf '%s' "$root" | cksum | cut -d' ' -f1)"
sock="$runtime/mux/${base:-project}-$hash.sock"
nvim --headless -u NONE --listen "$sock" </dev/null >/dev/null 2>&1 &
server_pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -S "$sock" ] && break
  sleep 0.05
done
[ -S "$sock" ] || fail "fixture server did not create its socket"
printf '%s\n' "$server_pid" >"${sock%.sock}.pid"
printf '%s\n' '#!/usr/bin/env bash' 'exit 1' >"$bin/fail-nvim"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$bin/sleep"
chmod +x "$bin/fail-nvim" "$bin/sleep"
if PATH="$bin:$PATH" \
  HOME="$work/home" \
  XDG_STATE_HOME="$work/stop-state" \
  XDG_RUNTIME_DIR="$runtime" \
  MUX_NVIM="$bin/fail-nvim" \
  bash "$MUX_SOURCE" stop "$root" 2>"$work/stop-error"; then
  fail "stop succeeded after its RPC failed"
fi
kill -0 "$server_pid" 2>/dev/null || fail "fixture server unexpectedly exited"
[ -S "$sock" ] || fail "stop unlinked a live server socket"
grep -Fq 'socket left intact' "$work/stop-error" || fail "stop failure did not explain socket preservation"

if bash "$REPO_ROOT/scripts/bin/remote.sh" one two >/dev/null 2>&1; then
  fail "remote connector accepted multiple projects"
fi
