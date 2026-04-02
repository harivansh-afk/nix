#!/usr/bin/env bash
set -euo pipefail

initial_query="${INITIAL_QUERY:-}"

search_script="$(mktemp)"
cleanup() {
  rm -f "$search_script"
}
trap cleanup EXIT

cat > "$search_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

query="${1:-}"

if [[ -z "$query" ]]; then
  exit 0
fi

paths=(
  "$HOME/.claude/history.jsonl"
  "$HOME/.claude/transcripts"
  "$HOME/.claude/projects"
  "$HOME/.codex/history.jsonl"
  "$HOME/.codex/session_index.jsonl"
  "$HOME/.codex/sessions"
  "$HOME/.codex/memories"
)

args=()
for path in "${paths[@]}"; do
  [[ -e "$path" ]] && args+=("$path")
done

[[ "${#args[@]}" -gt 0 ]] || exit 0

rg --json --line-number --smart-case --glob '*.jsonl' --glob '*.md' -- "$query" "${args[@]}" 2>/dev/null \
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
  --header 'Type to search netty default Claude and Codex state' \
  --bind "start:reload:$search_script {q} || true" \
  --bind "change:reload:sleep 0.1; $search_script {q} || true"
