# mux: per-project Neovim server launcher (replaces tmux).
# Each project (git root) gets one `nvim --headless --listen <socket>` server
# (running the real config, with lua/mux activated via -c + MUX=1). Clients
# attach via `--remote-ui`; switch projects from inside nvim with <c-b>f.

set -euo pipefail

NVIM="${MUX_NVIM:-nvim}"
if [ -n "${XDG_RUNTIME_DIR:-}" ]; then
  RUNTIME_BASE="$XDG_RUNTIME_DIR"
elif [ "$(uname -s)" = "Darwin" ]; then
  tmpdir="${TMPDIR:-/tmp}"
  RUNTIME_BASE="${tmpdir%/}"
else
  RUNTIME_BASE="/run/user/$(id -u)"
fi
RUNTIME_DIR="$RUNTIME_BASE/mux"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/nvim/mux"
LAST_FILE="$STATE_DIR/last"
HISTORY_FILE="$STATE_DIR/history"
LOG_DIR="$STATE_DIR/logs"
SCRIPT_SELF="$(command -v -- "${BASH_SOURCE[0]:-$0}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]:-$0}")"

die() {
  printf 'mux: %s\n' "$1" >&2
  exit 1
}

command -v "$NVIM" >/dev/null 2>&1 || die "neovim ($NVIM) not found"

detach_run() {
  if command -v setsid >/dev/null 2>&1; then
    setsid "$@" >/dev/null 2>&1 &
  else
    nohup "$@" >/dev/null 2>&1 &
  fi
}

slug() {
  local path="$1" base hash
  base="$(basename "$path" | tr -c 'A-Za-z0-9._-' '_')"
  hash="$(printf '%s' "$path" | cksum | cut -d' ' -f1)"
  printf '%s-%s' "${base:-project}" "$hash"
}

workspace_root_for() {
  local path="$1" root dir parent
  root="$(git -C "$path" rev-parse --show-toplevel 2>/dev/null)" && {
    printf '%s\n' "$root"
    return 0
  }
  dir="$(realpath "$path" 2>/dev/null)" || return 1
  [ -d "$dir" ] || dir="$(dirname "$dir")"
  while [ -n "$dir" ]; do
    if [ -e "$dir/.git" ] || [ -e "$dir/.jj" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    parent="$(dirname "$dir")"
    [ "$parent" != "$dir" ] || break
    dir="$parent"
  done
  return 1
}

root_for() {
  local path="$1" root
  root="$(workspace_root_for "$path")" || die "not in a git or jj workspace: $path"
  printf '%s\n' "$root"
}

socket_for() {
  printf '%s/%s.sock' "$RUNTIME_DIR" "$(slug "$1")"
}

session_for() {
  printf '%s/sessions/%s.vim' "$STATE_DIR" "$(slug "$1")"
}

restore_for() {
  printf '%s/sessions/%s.restore' "$STATE_DIR" "$(slug "$1")"
}

log_for() {
  printf '%s/%s.log' "$LOG_DIR" "$(slug "$1")"
}

timestamp() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

log_line() {
  local file="$1"
  shift
  mkdir -p "$LOG_DIR"
  : >>"$file"
  chmod 600 "$file" 2>/dev/null || true
  printf '[%s] %s\n' "$(timestamp)" "$*" >>"$file"
}

log_tail() {
  local file="$1" lines="${MUX_LOG_LINES:-80}"
  [ -f "$file" ] || return 0
  printf 'mux: log: %s\n' "$file" >&2
  tail -n "$lines" "$file" >&2
}

process_group_for() {
  ps -o pgid= -p "$1" 2>/dev/null | tr -d '[:space:]'
}

terminate_process_group() {
  local pid="$1" logf="$2" pgid
  pgid="$(process_group_for "$pid")"
  if [ -n "$pgid" ]; then
    log_line "$logf" "mux: terminating process group pgid=$pgid pid=$pid"
    kill -TERM -- "-$pgid" 2>/dev/null || true
    sleep 0.5
    kill -KILL -- "-$pgid" 2>/dev/null || true
  else
    log_line "$logf" "mux: terminating process pid=$pid"
    kill -TERM "$pid" 2>/dev/null || true
    sleep 0.5
    kill -KILL "$pid" 2>/dev/null || true
  fi
}

is_live() {
  local sock="$1" pidf pid
  [ -S "$sock" ] || return 1
  pidf="${sock%.sock}.pid"
  if [ -f "$pidf" ]; then
    pid=""
    IFS= read -r pid <"$pidf" 2>/dev/null || true
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
    return 1
  fi
  "$NVIM" --server "$sock" --remote-expr 1 </dev/null >/dev/null 2>&1
}

rpc() {
  "$NVIM" --server "$1" --remote-expr \
    "luaeval('(function() require([[mux]]).$2 return 1 end)()')" \
    </dev/null >/dev/null 2>&1 || true
}

bootstrap_direnv_mode() {
  case "${MUX_BOOTSTRAP_DIRENV:-1}" in
  1 | true | yes | on | "")
    printf '1'
    ;;
  0 | false | no | off)
    printf '0'
    ;;
  *)
    die "unknown MUX_BOOTSTRAP_DIRENV mode: ${MUX_BOOTSTRAP_DIRENV}"
    ;;
  esac
}

bootstrap_server() {
  local root="$1" sock="$2" logf="$3" bootstrap_direnv="$4"
  local direnv_env rc start end bootpidf
  umask 077
  bootpidf="${sock%.sock}.boot.pid"
  printf '%s\n' "$$" >"$bootpidf"
  cd "$root" || exit 1
  mkdir -p "$LOG_DIR" "$(dirname "$(session_for "$root")")"
  log_line "$logf" "== mux start =="
  log_line "$logf" "root=$root"
  log_line "$logf" "socket=$sock"
  log_line "$logf" "nvim=$NVIM"
  log_line "$logf" "bootstrap_direnv=$bootstrap_direnv"
  if [ "$bootstrap_direnv" = 1 ] && command -v direnv >/dev/null 2>&1; then
    log_line "$logf" "direnv: export bash timeout=${MUX_DIRENV_TIMEOUT:-120s}"
    start="$(date +%s)"
    set +e
    if command -v timeout >/dev/null 2>&1; then
      direnv_env="$(timeout --foreground "${MUX_DIRENV_TIMEOUT:-120s}" direnv export bash 2>>"$logf")"
      rc=$?
    else
      direnv_env="$(direnv export bash 2>>"$logf")"
      rc=$?
    fi
    set -e
    end="$(date +%s)"
    if [ "$rc" -eq 0 ]; then
      [ -n "$direnv_env" ] && eval "$direnv_env"
      log_line "$logf" "direnv: ok duration=$((end - start))s"
    else
      log_line "$logf" "direnv: failed rc=$rc duration=$((end - start))s; continuing without bootstrap environment"
    fi
  elif [ "$bootstrap_direnv" = 0 ]; then
    log_line "$logf" "direnv: bootstrap disabled"
  else
    log_line "$logf" "direnv: not found"
  fi
  export MUX=1
  export MUX_ROOT="$root"
  export MUX_LOG_FILE="$logf"
  MUX_SESSION_FILE="$(session_for "$root")"
  export MUX_SESSION_FILE
  export NVIM_LOG_FILE="${NVIM_LOG_FILE:-$LOG_DIR/$(slug "$root").nvim.log}"
  log_line "$logf" "nvim: exec --headless --listen $sock"
  exec "$NVIM" --headless --listen "$sock" \
    -c "lua pcall(function() require('mux').setup() end)" \
    </dev/null >/dev/null 2>/dev/null
}

ensure() {
  local path root sock logf bootstrap_direnv start_timeout limit i pid rc bootpidf bootpid monitor_pid
  path="${1:-$PWD}"
  root="$(root_for "$path")"
  sock="$(socket_for "$root")"
  logf="$(log_for "$root")"
  bootpidf="${sock%.sock}.boot.pid"
  bootstrap_direnv="$(bootstrap_direnv_mode)"
  start_timeout="${MUX_START_TIMEOUT:-150}"
  case "$start_timeout" in
  *[!0-9]* | "")
    die "MUX_START_TIMEOUT must be an integer number of seconds"
    ;;
  esac
  mkdir -p "$RUNTIME_DIR" "$LOG_DIR"
  if [ -e "$sock" ] && ! is_live "$sock"; then
    rm -f "$sock" "$bootpidf"
  fi
  if ! is_live "$sock"; then
    : >>"$logf"
    chmod 600 "$logf" 2>/dev/null || true
    rm -f "$bootpidf"
    detach_run "$SCRIPT_SELF" __bootstrap "$root" "$sock" "$logf" "$bootstrap_direnv"
    pid=$!
    limit=$((start_timeout * 20))
    i=0
    while [ "$i" -lt "$limit" ]; do
      if [ -z "${bootpid:-}" ] && [ -f "$bootpidf" ]; then
        IFS= read -r bootpid <"$bootpidf" 2>/dev/null || true
      fi
      monitor_pid="${bootpid:-$pid}"
      if is_live "$sock"; then
        log_line "$logf" "mux: socket live after $i polls"
        mark_restore "$root"
        printf '%s\n' "$sock"
        return 0
      fi
      if ! kill -0 "$monitor_pid" 2>/dev/null; then
        set +e
        wait "$pid" 2>/dev/null
        rc=$?
        set -e
        if is_live "$sock"; then
          log_line "$logf" "mux: socket live after bootstrap exit rc=$rc"
          mark_restore "$root"
          printf '%s\n' "$sock"
          return 0
        fi
        log_line "$logf" "mux: bootstrap exited before socket rc=$rc"
        log_tail "$logf"
        die "server did not start at $sock"
      fi
      sleep 0.05
      i=$((i + 1))
    done
    if [ -z "${bootpid:-}" ] && [ -f "$bootpidf" ]; then
      IFS= read -r bootpid <"$bootpidf" 2>/dev/null || true
    fi
    monitor_pid="${bootpid:-$pid}"
    log_line "$logf" "mux: startup timeout after ${start_timeout}s"
    terminate_process_group "$monitor_pid" "$logf"
    wait "$pid" 2>/dev/null || true
    rm -f "$sock" "$bootpidf"
    log_tail "$logf"
    die "server did not start at $sock"
  fi
  mark_restore "$root"
  printf '%s\n' "$sock"
}

record_last() {
  mkdir -p "$STATE_DIR"
  printf '%s\n' "$1" >"$LAST_FILE"
}

push_history() {
  local root="$1" tmp
  [ -n "$root" ] || return 0
  mkdir -p "$STATE_DIR"
  tmp="$(mktemp "$STATE_DIR/.history.XXXXXX")" || return 0
  if [ -f "$HISTORY_FILE" ]; then
    grep -vxF -- "$root" "$HISTORY_FILE" 2>/dev/null | tail -n 49 >>"$tmp" || true
  fi
  printf '%s\n' "$root" >>"$tmp"
  mv -f "$tmp" "$HISTORY_FILE"
}

forget_history() {
  local root="$1" tmp
  [ -n "$root" ] || return 0
  [ -f "$HISTORY_FILE" ] || return 0
  tmp="$(mktemp "$STATE_DIR/.history.XXXXXX")" || return 0
  grep -vxF -- "$root" "$HISTORY_FILE" 2>/dev/null >>"$tmp" || true
  mv -f "$tmp" "$HISTORY_FILE"
}

clear_last() {
  local root="$1" cur
  [ -f "$LAST_FILE" ] || return 0
  cur="$(head -n1 "$LAST_FILE" 2>/dev/null || true)"
  [ "$cur" = "$root" ] && rm -f "$LAST_FILE" || true
}

mark_restore() {
  local root="$1" rf
  [ -n "$root" ] || return 0
  mkdir -p "$STATE_DIR/sessions"
  rf="$(restore_for "$root")"
  printf '%s\n' "$root" >"$rf"
  chmod 600 "$rf" 2>/dev/null || true
}

unmark_restore() {
  local root="$1"
  [ -n "$root" ] || return 0
  rm -f "$(restore_for "$root")"
}

restore_marked() {
  local skip="${1:-}" mode="${2:-background}" rf root vimf
  [ -d "$STATE_DIR/sessions" ] || return 0
  for rf in "$STATE_DIR"/sessions/*.restore; do
    [ -e "$rf" ] || continue
    root=""
    IFS= read -r root <"$rf" 2>/dev/null || true
    [ -n "$root" ] || continue
    [ -z "$skip" ] || [ "$root" != "$skip" ] || continue
    [ -d "$root" ] || continue
    vimf="${rf%.restore}.vim"
    [ -f "$vimf" ] || continue
    if [ "$mode" = foreground ]; then
      ensure "$root" >/dev/null || true
    else
      "$SCRIPT_SELF" ensure "$root" >/dev/null 2>&1 &
    fi
  done
}

open_project() {
  local root sock
  root="$(root_for "${1:-$PWD}")"
  sock="$(ensure "$root")"
  record_last "$root"
  push_history "$root"
  cd "$root" || true
  env MUX=1 "$NVIM" --remote-ui --server "$sock"
  exec "${SHELL:-/bin/sh}"
}

resume() {
  local last lines n cwd
  last=""
  [ -f "$LAST_FILE" ] && last="$(head -n1 "$LAST_FILE" 2>/dev/null || true)"
  if [ -n "$last" ] && [ -d "$last" ]; then
    restore_marked "$last"
    open_project "$last"
    return
  fi
  restore_marked ""
  lines="$(list)"
  n="$(printf '%s' "$lines" | grep -c . || true)"
  if [ "$n" -eq 1 ]; then
    cwd="$(printf '%s\n' "$lines" | head -n1 | cut -f1)"
    if [ -n "$cwd" ] && [ "$cwd" != '?' ] && [ -d "$cwd" ]; then
      open_project "$cwd"
      return
    fi
  fi
  pick
}

# List sessions: live servers (running) plus stopped ones (a saved snapshot
# exists, recovered from its `.root` sidecar)
list_rows() {
  local sock cwd slug rootf rf root
  if [ -d "$RUNTIME_DIR" ]; then
    for sock in "$RUNTIME_DIR"/*.sock; do
      [ -e "$sock" ] || continue
      is_live "$sock" || continue
      slug="${sock##*/}"
      slug="${slug%.sock}"
      rootf="$STATE_DIR/sessions/$slug.root"
      cwd=""
      [ -f "$rootf" ] && IFS= read -r cwd <"$rootf" 2>/dev/null || true
      [ -n "$cwd" ] || continue
      printf '%s\t%s\t%s\n' "$cwd" "$sock" live
    done
  fi
  # stopped = snapshot+sidecar present but the project's server isn't live.
  if [ -d "$STATE_DIR/sessions" ]; then
    local dcwds=() dsocks=() dstats=() i
    for rf in "$STATE_DIR"/sessions/*.root; do
      [ -e "$rf" ] || continue
      root=""
      IFS= read -r root <"$rf" 2>/dev/null || true
      [ -n "$root" ] || continue
      slug="${rf##*/}"
      slug="${slug%.root}"
      sock="$RUNTIME_DIR/$slug.sock"
      if [ -d "$root" ]; then
        [ -f "${rf%.root}.vim" ] || continue
        if is_live "$sock"; then continue; fi
        printf '%s\t\t%s\n' "$root" stopped
      else
        dcwds+=("$root")
        dsocks+=("")
        dstats+=("dead")
      fi
    done
    for i in "${!dcwds[@]}"; do
      printf '%s\t%s\t%s\n' "${dcwds[$i]}" "${dsocks[$i]}" "${dstats[$i]}"
    done
  fi
  zoxide query -l 2>/dev/null | while IFS= read -r root; do
    [ -n "$root" ] || continue
    root="$(workspace_root_for "$root")" || continue
    printf '%s\t\t%s\n' "$root" dir
  done || true
}

list_projects() {
  list_rows | awk -F'\t' '
    function norm(p) {
      gsub(/\/+$/, "", p)
      return p == "" ? "/" : p
    }
    function parent_seen(p, parent) {
      parent = p
      while (parent != "" && parent != "/") {
        sub(/\/[^\/]*$/, "", parent)
        if (parent == "") {
          parent = "/"
        }
        if (parent != "/" && all[parent]) {
          return 1
        }
      }
      return 0
    }
    NF {
      cwd[++n] = $1
      sock[n] = $2
      status[n] = $3
      key[n] = norm($1)
      if (key[n] != "?" && key[n] != "") {
        all[key[n]] = 1
      }
    }
    END {
      for (i = 1; i <= n; i++) {
        p = key[i]
        if (p == "" || p == "?" || seen[p]) {
          continue
        }
        if (status[i] == "dir" && parent_seen(p)) {
          continue
        }
        seen[p] = 1
        print cwd[i] "\t" sock[i] "\t" status[i]
      }
    }
  '
}

list() {
  local lines line rest cwd sock status i w=0 c tag
  local cwds=() socks=() stats=() disp=()
  lines="$(list_projects)"
  [ -n "$lines" ] || return 0
  if [ -t 1 ]; then
    local reset green amber red
    reset=$'\033[0m'
    green=$'\033[32m'
    amber=$'\033[33m'
    red=$'\033[31m'
    while IFS= read -r line; do
      cwd="${line%%$'\t'*}"
      rest="${line#*$'\t'}"
      sock="${rest%%$'\t'*}"
      status="${rest#*$'\t'}"
      cwds+=("$cwd")
      socks+=("$sock")
      stats+=("$status")
      disp+=("${cwd/#$HOME/\~}")
    done <<<"$lines"
    for cwd in "${disp[@]}"; do [ "${#cwd}" -gt "$w" ] && w="${#cwd}"; done
    for i in "${!disp[@]}"; do
      case "${stats[$i]}" in
      live) c="$green" ;;
      stopped) c="$amber" ;;
      dead) c="$red" ;;
      *) c="" ;;
      esac
      if [ "${stats[$i]}" = dir ]; then
        tag="$(printf '%-9s' '')"
      else
        tag="$(printf '%-9s' "[${stats[$i]}]")"
      fi
      if [ -n "$c" ]; then
        printf '%s%s%s %-*s  %s\n' "$c" "$tag" "$reset" "$w" "${disp[$i]}" "${socks[$i]}"
      else
        printf '%s %-*s  %s\n' "$tag" "$w" "${disp[$i]}" "${socks[$i]}"
      fi
    done
  else
    printf '%s\n' "$lines"
  fi
}

pick() {
  local choice
  choice="$(list | awk -F'\t' '$3 != "dead" { print $1 }' | sed "s|^$HOME|~|" | fzf --prompt 'project> ')" || return 0
  [ -n "$choice" ] || return 0
  open_project "${choice/#\~/$HOME}"
}

show_log() {
  local follow=0 root logf lines
  case "${1:-}" in
  -f | --follow)
    follow=1
    shift
    ;;
  esac
  root="$(root_for "${1:-$PWD}")"
  logf="$(log_for "$root")"
  lines="${MUX_LOG_LINES:-120}"
  [ -f "$logf" ] || die "no log for $root"
  if [ "$follow" -eq 1 ]; then
    tail -n "$lines" -f "$logf"
  else
    tail -n "$lines" "$logf"
  fi
}

usage() {
  cat <<'EOF'
mux: per-project neovim server launcher

  mux [<path>]        open the project at <path> (default: cwd), spawning if needed
  mux open [<path>]   alias for mux [<path>]
  mux ensure [<path>] print a live server socket for the project, spawning if needed
  mux list            list projects: live + stopped + dead + dir (cwd<TAB>socket<TAB>status)
  mux pick            fzf-pick a project from mux list and open it
  mux stop [<path>]   stop the project's server (saved session restored next open)
  mux kill [<path>]   hard-remove the project: stop + delete its saved session
  mux clean           delete unrevivable session junk (orphan snapshots, stale sockets)
  mux restore         start every session marked for login restore
  mux reload [<path>] reload the project in place (apply edited config)
  mux reload --all    reload every live session
  mux save [<path>]   snapshot the project's session now, without quitting
  mux save --all      snapshot every live session
  mux log [<path>]    show the project's recent startup/server log
  mux log -f [<path>] follow the project's startup/server log
  mux help            this help (also -h | --help)

Environment:
  MUX_START_TIMEOUT       seconds to wait for cold startup (default: 150)
  MUX_DIRENV_TIMEOUT      timeout passed to direnv export (default: 120s)
  MUX_BOOTSTRAP_DIRENV    1/0, run direnv before starting nvim (default: 1)
  MUX_LOG_LINES           lines shown by mux log and failure tails

Inside nvim, switch projects with <c-b>f, detach with <c-b>d.
EOF
}

stop_server() {
  local root sock i
  root="$(root_for "${1:-$PWD}")"
  sock="$(socket_for "$root")"
  unmark_restore "$root"
  if is_live "$sock"; then
    rpc "$sock" 'stop_session()'
    i=0
    while [ "$i" -lt 100 ] && is_live "$sock"; do
      sleep 0.05
      i=$((i + 1))
    done
  fi
  rm -f "$sock" "${sock%.sock}.boot.pid"
}

kill_server() {
  local target root sock sf i
  target="${1:-$PWD}"
  root="$(root_for "$target" 2>/dev/null || true)"
  [ -n "$root" ] || root="$target"
  sock="$(socket_for "$root")"
  sf="$(session_for "$root")"
  if is_live "$sock"; then
    # hard kill: set the in-Neovim no-save guard and quit, so VimLeavePre can't
    # re-save the snapshot we're about to delete.
    rpc "$sock" 'kill_session()'
    i=0
    while [ "$i" -lt 100 ] && is_live "$sock"; do
      sleep 0.05
      i=$((i + 1))
    done
  fi
  rm -f "$sock" "${sock%.sock}.boot.pid" "$sf" "${sf%.vim}.root" "${sf%.vim}.restore"
  forget_history "$root"
  clear_last "$root"
}

clean() {
  local f slug root vim restore sock rootval
  if [ -d "$STATE_DIR/sessions" ]; then
    local slugs=()
    for f in "$STATE_DIR"/sessions/*.root "$STATE_DIR"/sessions/*.vim "$STATE_DIR"/sessions/*.restore; do
      [ -e "$f" ] || continue
      slug="$(basename "$f")"
      slug="${slug%.root}"
      slug="${slug%.vim}"
      slug="${slug%.restore}"
      case " ${slugs[*]-} " in
      *" $slug "*) ;;
      *) slugs+=("$slug") ;;
      esac
    done
    for slug in ${slugs[@]+"${slugs[@]}"}; do
      if is_live "$RUNTIME_DIR/$slug.sock"; then continue; fi
      root="$STATE_DIR/sessions/$slug.root"
      vim="$STATE_DIR/sessions/$slug.vim"
      restore="$STATE_DIR/sessions/$slug.restore"
      rootval=""
      if [ -f "$root" ]; then
        rootval="$(head -n1 "$root" 2>/dev/null || true)"
      fi
      if [ -f "$vim" ] && [ -n "$rootval" ] && [ -d "$rootval" ]; then
        continue
      fi
      if [ -n "$rootval" ] && [ ! -d "$rootval" ]; then
        continue
      fi
      rm -f "$vim" "$root" "$restore"
    done
  fi
  if [ -d "$RUNTIME_DIR" ]; then
    for sock in "$RUNTIME_DIR"/*.sock; do
      [ -e "$sock" ] || continue
      if is_live "$sock"; then continue; fi
      rm -f "$sock" "${sock%.sock}.boot.pid"
    done
  fi
}

reload_one() {
  local root sock logf uis mode start end i
  root="$(root_for "${1:-$PWD}")"
  sock="$(socket_for "$root")"
  logf="$(log_for "$root")"
  is_live "$sock" || return 0
  uis="$("$NVIM" --server "$sock" --remote-expr 'len(nvim_list_uis())' </dev/null 2>/dev/null || true)"
  uis="${uis//[^0-9]/}"
  mode="ui"
  [ "${uis:-0}" -gt 0 ] || mode="restart"
  start="$(date +%s)"
  log_line "$logf" "mux reload: begin mode=$mode uis=${uis:-0}"
  if [ "${uis:-0}" -gt 0 ]; then
    rpc "$sock" 'reload()'
  else
    "$NVIM" --server "$sock" --remote-expr 'execute("silent! wall | qall!")' </dev/null >/dev/null 2>&1 || true
    i=0
    while [ "$i" -lt 100 ] && is_live "$sock"; do
      sleep 0.05
      i=$((i + 1))
    done
    ensure "$root" >/dev/null
  fi
  end="$(date +%s)"
  log_line "$logf" "mux reload: end duration=$((end - start))s"
}

reload_all() {
  local sock cwd start end count=0
  [ -d "$RUNTIME_DIR" ] || return 0
  start="$(date +%s)"
  for sock in "$RUNTIME_DIR"/*.sock; do
    [ -e "$sock" ] || continue
    is_live "$sock" || continue
    cwd="$("$NVIM" --server "$sock" --remote-expr 'luaeval("vim.env.MUX_ROOT or \"\"")' </dev/null 2>/dev/null || true)"
    [ -n "$cwd" ] || cwd="$("$NVIM" --server "$sock" --remote-expr 'getcwd()' </dev/null 2>/dev/null || true)"
    if [ -n "$cwd" ]; then
      count=$((count + 1))
      reload_one "$cwd"
    fi
  done
  end="$(date +%s)"
  log_line "$LOG_DIR/reload-all.log" "mux reload --all: end count=$count duration=$((end - start))s"
}

save_one() {
  local sock
  sock="$(socket_for "$(root_for "${1:-$PWD}")")"
  is_live "$sock" || return 0
  rpc "$sock" 'save_session()'
}

save_all() {
  local sock
  [ -d "$RUNTIME_DIR" ] || return 0
  for sock in "$RUNTIME_DIR"/*.sock; do
    [ -e "$sock" ] || continue
    is_live "$sock" || continue
    rpc "$sock" 'save_session()'
  done
}

case "${1:-}" in
__bootstrap)
  shift
  bootstrap_server "$@"
  ;;
ensure)
  shift
  ensure "${1:-$PWD}"
  ;;
list)
  list
  ;;
pick)
  pick
  ;;
stop)
  shift
  stop_server "${1:-$PWD}"
  ;;
kill)
  shift
  kill_server "${1:-$PWD}"
  ;;
clean)
  clean
  ;;
restore)
  restore_marked "" foreground
  ;;
reload)
  shift
  if [ "${1:-}" = --all ] || [ "${1:-}" = -a ]; then
    reload_all
  else
    reload_one "${1:-$PWD}"
  fi
  ;;
save)
  shift
  if [ "${1:-}" = --all ] || [ "${1:-}" = -a ]; then
    save_all
  else
    save_one "${1:-$PWD}"
  fi
  ;;
log)
  shift
  show_log "$@"
  ;;
help | -h | --help)
  usage
  ;;
open)
  shift
  open_project "${1:-$PWD}"
  ;;
"")
  resume
  ;;
-*)
  die "unknown option: $1 (try --help)"
  ;;
*)
  [ -d "$1" ] || die "unknown command: $1 (try --help)"
  open_project "$1"
  ;;
esac
