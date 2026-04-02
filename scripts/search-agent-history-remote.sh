#!/usr/bin/env bash
set -euo pipefail

root="${AGENT_HISTORY_ROOT:-$HOME/.local/share/agent-history/raw}"
initial_query="${INITIAL_QUERY:-}"

if [[ ! -d "$root" ]]; then
  printf 'Agent history root not found: %s\n' "$root" >&2
  exit 1
fi

search_script="$(mktemp)"
cleanup() {
  rm -f "$search_script"
}
trap cleanup EXIT

cat > "$search_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

root="${AGENT_HISTORY_ROOT:?}"
query="${1:-}"

if [[ -z "$query" ]]; then
  exit 0
fi

rg --json --line-number --smart-case --glob '*.jsonl' -- "$query" "$root" 2>/dev/null \
  | jq -r '
      select(.type == "match")
      | [
          .data.path.text,
          (.data.line_number | tostring),
          (.data.lines.text | gsub("[\r\n\t]+"; " "))
        ]
      | @tsv
    '
EOF

chmod +x "$search_script"
export AGENT_HISTORY_ROOT="$root"

fzf --phony --ansi --disabled \
  --query "$initial_query" \
  --prompt 'history> ' \
  --delimiter $'\t' \
  --with-nth=1,2,3 \
  --preview '
    file=$(printf "%s" {} | cut -f1)
    line=$(printf "%s" {} | cut -f2)
    [[ -n "$file" ]] || exit 0
    [[ "$line" =~ ^[0-9]+$ ]] || line=1
    start=$(( line > 20 ? line - 20 : 1 ))
    end=$(( line + 20 ))
    sed -n "${start},${end}p" "$file"
  ' \
  --preview-window=right:70%:wrap \
  --header 'Type to search archived Claude and Codex logs on netty' \
  --bind "start:reload:$search_script {q} || true" \
  --bind "change:reload:sleep 0.1; $search_script {q} || true"
