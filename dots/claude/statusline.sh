#!/usr/bin/env bash

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
DIM='\033[2m'
RESET='\033[0m'

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir')
model_id=$(echo "$input" | jq -r '.model.id // ""')
dir_name=$(basename "$cwd")

if [[ -n "$model_id" ]]; then
  if [[ "$model_id" =~ opus ]]; then
    model="Opus"
  elif [[ "$model_id" =~ sonnet ]]; then
    model="Sonnet"
  elif [[ "$model_id" =~ haiku ]]; then
    model="Haiku"
  elif [[ "$model_id" =~ fable ]]; then
    model="Fable"
  else
    model="Claude"
  fi
else
  model="Claude"
fi

autocompact_enabled=true
token_detail_enabled=true
show_delta_enabled=true
autocompact=""
token_detail=""
show_delta=""
ac_info=""
delta_info=""

if [[ ! -f ~/.claude/statusline.conf ]]; then
  mkdir -p ~/.claude
  cat >~/.claude/statusline.conf <<'EOF'
# Autocompact setting - sync with Claude Code's /config
autocompact=true

# Token display format
token_detail=true

# Show token delta since last refresh (adds file I/O on every refresh)
# Disable if you don't need it to reduce overhead
show_delta=true
EOF
fi

if [[ -f ~/.claude/statusline.conf ]]; then
  # shellcheck source=/dev/null
  source ~/.claude/statusline.conf
  if [[ "$autocompact" == "false" ]]; then
    autocompact_enabled=false
  fi
  if [[ "$token_detail" == "false" ]]; then
    token_detail_enabled=false
  fi
  if [[ "$show_delta" == "false" ]]; then
    show_delta_enabled=false
  fi
fi

context_info=""
total_size=$(echo "$input" | jq -r '.context_window.context_window_size // 0')
current_usage=$(echo "$input" | jq '.context_window.current_usage')

if [[ "$total_size" -gt 0 && "$current_usage" != "null" ]]; then

  input_tokens=$(echo "$current_usage" | jq -r '.input_tokens // 0')
  cache_creation=$(echo "$current_usage" | jq -r '.cache_creation_input_tokens // 0')
  cache_read=$(echo "$current_usage" | jq -r '.cache_read_input_tokens // 0')

  used_tokens=$((input_tokens + cache_creation + cache_read))

  free_tokens=$((total_size - used_tokens))

  if [[ "$autocompact_enabled" == "true" ]]; then
    autocompact_buffer=$((total_size * 225 / 1000))
    buffer_k=$(awk "BEGIN {printf \"%.0f\", $autocompact_buffer / 1000}")
    ac_info=" ${DIM}[AC:${buffer_k}k]${RESET}"
  else
    ac_info=" ${DIM}[AC:off]${RESET}"
  fi

  if [[ "$free_tokens" -lt 0 ]]; then
    free_tokens=0
  fi

  free_pct=$(awk "BEGIN {printf \"%.1f\", ($free_tokens * 100.0 / $total_size)}")
  free_pct_int=${free_pct%.*}

  if [[ "$token_detail_enabled" == "true" ]]; then

    free_display=$(awk -v n="$free_tokens" 'BEGIN { printf "%\047d", n }')
  else
    free_display=$(awk "BEGIN {printf \"%.1fk\", $free_tokens / 1000}")
  fi

  if [[ "$free_pct_int" -gt 50 ]]; then
    ctx_color="$GREEN"
  elif [[ "$free_pct_int" -gt 25 ]]; then
    ctx_color="$YELLOW"
  else
    ctx_color="$RED"
  fi

  context_info=" | ${ctx_color}${free_display} free (${free_pct}%)${RESET}"

  if [[ "$show_delta_enabled" == "true" ]]; then
    state_file=~/.claude/statusline.state
    has_prev=false
    prev_tokens=0
    if [[ -f "$state_file" ]]; then
      has_prev=true

      prev_tokens=$(tail -1 "$state_file" 2>/dev/null | cut -d',' -f2)
      prev_tokens=${prev_tokens:-0}
    fi

    delta=$((used_tokens - prev_tokens))

    if [[ "$has_prev" == "true" && "$delta" -gt 0 ]]; then
      if [[ "$token_detail_enabled" == "true" ]]; then
        delta_display=$(awk -v n="$delta" 'BEGIN { printf "%\047d", n }')
      else
        delta_display=$(awk "BEGIN {printf \"%.1fk\", $delta / 1000}")
      fi
      delta_info=" ${DIM}[+${delta_display}]${RESET}"
    fi

    echo "$(date +%s),$used_tokens" >>"$state_file"
  fi
fi

echo -e "${DIM}[${model}]${RESET} ${BLUE}${dir_name}${RESET}${context_info}${delta_info}${ac_info}"
