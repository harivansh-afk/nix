# hrd: herdr remote console + federated session listing, the herdr sibling
# of mux's remote layer. Shares the baked-in connector catalog from
# lib/remotes.nix: `hrd <name>` runs the remote herdr client over mosh
# (roaming-safe; remote config is identical since nix renders it on every
# host), `--ssh` overrides to herdr's native ssh attach (`herdr --remote`,
# local client + local keybindings), and `hrd ls` federates
# `herdr session list --json` + `herdr workspace list` across every
# reachable remote, rendered mux-style (live-first, colored [host] tags).

set -euo pipefail

HRD_LIST_TIMEOUT="${HRD_LIST_TIMEOUT:-1}"
LIVE_MARKER="▍"

die() {
  printf 'hrd: %s\n' "$1" >&2
  exit 1
}

usage() {
  cat <<'EOF'
hrd: herdr remote console + federated session list

  hrd                attach the local herdr session
  hrd <name>         attach <name>'s herdr over mosh (catalog: lib/remotes.nix)
  hrd <name> --ssh   transport override: herdr --remote <host> (native ssh attach)
  hrd ls             sessions + workspaces across all remotes
                      (TSV when piped: host<TAB>session<TAB>status<TAB>workspaces)
  hrd help           this help (also -h | --help)

Environment:
  HRD_LIST_TIMEOUT   ssh connect timeout for hrd ls probes (default: 1)
  HRD_REMOTES_FILE   override the baked-in remotes catalog (name host lines)
EOF
}

remotes_catalog() {
  if [ -n "${HRD_REMOTES_FILE:-}" ] && [ -f "$HRD_REMOTES_FILE" ]; then
    cat "$HRD_REMOTES_FILE"
    return 0
  fi
  cat <<'EOF'
@HRD_REMOTES@
EOF
}

local_name() {
  local short
  short="$(hostname -s 2>/dev/null || hostname 2>/dev/null || printf local)"
  short="${short%%.*}"
  case "$short" in
  spark-ix | spark) printf 'spark\n' ;;
  *) printf '%s\n' "$short" ;;
  esac
}

# Resolve a catalog name to its ssh host; fails for unknown names.
catalog_host() {
  local line
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if [ "${line%% *}" = "$1" ]; then
      printf '%s\n' "${line#* }"
      return 0
    fi
  done < <(remotes_catalog)
  return 1
}

# One probe = one round trip: sessions JSON plus (when a server is running)
# the workspace list JSON; herdr prints one JSON document per command.
PROBE_CMD='herdr session list --json 2>/dev/null; herdr workspace list 2>/dev/null'

# Turn a probe's JSON stream into TSV session rows:
# session<TAB>status<TAB>workspace summary (workspaces only attach to the
# running default session - that is the one the socket commands talk to).
rows_from_json() {
  jq -rs '
    (map(.sessions? // empty) | add // []) as $sessions
    | (map(.result.workspaces? // empty) | add // []) as $ws
    | ($ws | map("\(.number):\(.label) (\(.agent_status // "-"))") | join("  ")) as $wsline
    | $sessions[]
    | [
        .name,
        (if .running then "running" else "stopped" end),
        (if .running and (.default // false) then $wsline else "" end)
      ]
    | @tsv
  ' 2>/dev/null
}

# Prefix stdin TSV rows with a host column.
tag_rows() {
  awk -F'\t' -v host="$1" '$1 != "" { print host "\t" $0 }'
}

# Federated list: local rows first, then each catalog remote probed in
# parallel over ssh. Always TSV: host<TAB>session<TAB>status<TAB>workspaces.
# Unreachable hosts (or hosts without herdr) are omitted.
list_all() (
  local me name host tmpdir line i=0
  local pids=() outs=()
  me="$(local_name)"
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/hrd-ls.XXXXXX")"
  trap 'rm -rf -- "$tmpdir"' EXIT
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    name="${line%% *}"
    host="${line#* }"
    [ -n "$name" ] && [ -n "$host" ] || continue
    { [ "$name" = "$me" ] || [ "$host" = "$me" ]; } && continue
    outs+=("$tmpdir/$i")
    (
      ssh -o BatchMode=yes -o ConnectTimeout="$HRD_LIST_TIMEOUT" \
        -o StrictHostKeyChecking=accept-new \
        "$host" "$PROBE_CMD" </dev/null 2>/dev/null |
        rows_from_json | tag_rows "$name" >"$tmpdir/$i" || true
    ) &
    pids+=("$!")
    i=$((i + 1))
  done < <(remotes_catalog)

  if command -v herdr >/dev/null 2>&1; then
    eval "$PROBE_CMD" | rows_from_json | tag_rows "$me"
  fi

  for pid in "${pids[@]+"${pids[@]}"}"; do
    wait "$pid" || true
  done
  for out in "${outs[@]+"${outs[@]}"}"; do
    cat "$out"
  done
)

# Rank federated rows running-first, stable within rank.
sort_rows() {
  awk -F'\t' '{ print (($3 == "running") ? 1 : 2) "\t" $0 }' | sort -s -k1,1n | cut -f2-
}

# Render federated TSV rows (stdin) for humans: one line per row - live
# marker + colored [host] tag + workspaces inline (or plain running/stopped).
# The session name only appears when it is not "default". Host colors mirror
# mux ls (blue, purple, orange, aqua) round-robin over sorted distinct hosts.
render_rows() {
  local name sess status ws tag detail i hw=0 h
  local names=() sesss=() stats=() wss=() hosts=()
  local reset=$'\033[0m' green=$'\033[32m'
  local palette=($'\033[34m' $'\033[35m' $'\033[38;5;208m' $'\033[36m')
  while IFS=$'\t' read -r name sess status ws; do
    [ -n "$name" ] && [ -n "$sess" ] || continue
    names+=("$name")
    sesss+=("$sess")
    stats+=("$status")
    wss+=("$ws")
  done
  [ "${#names[@]}" -gt 0 ] || return 0
  declare -A hcolor=()
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    hosts+=("$h")
  done < <(printf '%s\n' "${names[@]}" | sort -u)
  for i in "${!hosts[@]}"; do
    hcolor["${hosts[$i]}"]="${palette[$((i % ${#palette[@]}))]}"
  done
  for h in "${names[@]}"; do [ "${#h}" -gt "$hw" ] && hw="${#h}"; done
  for i in "${!names[@]}"; do
    tag="$(printf '%-*s' $((hw + 2)) "[${names[$i]}]")"
    if [ "${stats[$i]}" = running ]; then
      printf '%s%s%s ' "$green" "$LIVE_MARKER" "$reset"
      detail="${wss[$i]:-running}"
    else
      printf '  '
      detail="${stats[$i]}"
    fi
    [ "${sesss[$i]}" = default ] || detail="${sesss[$i]}: $detail"
    printf '%s%s%s %s\n' "${hcolor[${names[$i]}]}" "$tag" "$reset" "$detail"
  done
}

attach() {
  local transport=mosh name="" host me arg
  for arg in "$@"; do
    case "$arg" in
    --ssh) transport=ssh ;;
    -*) usage >&2 && exit 2 ;;
    *)
      [ -z "$name" ] || { usage >&2 && exit 2; }
      name="$arg"
      ;;
    esac
  done
  me="$(local_name)"
  if [ -z "$name" ] || [ "$name" = "$me" ] || [ "$name" = local ] || [ "$name" = . ]; then
    exec herdr
  fi
  host="$(catalog_host "$name")" || die "unknown remote: $name"
  if [ "$transport" = ssh ]; then
    exec herdr --remote "$host"
  fi
  exec mosh "$host" -- herdr
}

case "${1:-}" in
ls | list)
  if [ -t 1 ]; then
    list_all | sort_rows | render_rows
  else
    list_all
  fi
  ;;
help | -h | --help)
  usage
  ;;
*)
  attach "$@"
  ;;
esac
