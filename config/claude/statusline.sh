#!/bin/bash
# Full-featured status line with context window usage
# Usage: Copy to ~/.claude/statusline.sh and make executable
#
# Configuration:
# Create/edit ~/.claude/statusline.conf and set:
#
#   autocompact=true   (when autocompact is enabled in Claude Code - default)
#   autocompact=false  (when you disable autocompact via /config in Claude Code)
#
#   token_detail=true  (show exact token count like 64,000 - default)
#   token_detail=false (show abbreviated tokens like 64.0k)
#
#   show_delta=true    (show token delta since last refresh like [+2,500] - default)
#   show_delta=false   (disable delta display - saves file I/O on every refresh)
#
# When AC is enabled, 22.5% of context window is reserved for autocompact buffer.

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
DIM='\033[2m'
RESET='\033[0m'

# Read JSON input from stdin
input=$(cat)

# Extract information from JSON
cwd=$(echo "$input" | jq -r '.workspace.current_dir')
model_id=$(echo "$input" | jq -r '.model.id // ""')
dir_name=$(basename "$cwd")

# Parse model name from model ID (e.g., claude-opus-4-1 -> Opus)
if [[ -n "$model_id" ]]; then
    if [[ "$model_id" =~ opus ]]; then
        model="Opus"
    elif [[ "$model_id" =~ sonnet ]]; then
        model="Sonnet"
    elif [[ "$model_id" =~ haiku ]]; then
        model="Haiku"
    else
        model="Claude"
    fi
else
    model="Claude"
fi

# Read settings from ~/.claude/statusline.conf
# Sync this manually when you change settings in Claude Code via /config
autocompact_enabled=true
token_detail_enabled=true
show_delta_enabled=true
autocompact=""   # Will be set by sourced config
token_detail=""  # Will be set by sourced config
show_delta=""    # Will be set by sourced config
ac_info=""
delta_info=""

# Create config file with defaults if it doesn't exist
if [[ ! -f ~/.claude/statusline.conf ]]; then
    mkdir -p ~/.claude
    cat > ~/.claude/statusline.conf << 'EOF'
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

# Calculate context window - show remaining free space
context_info=""
total_size=$(echo "$input" | jq -r '.context_window.context_window_size // 0')
current_usage=$(echo "$input" | jq '.context_window.current_usage')

if [[ "$total_size" -gt 0 && "$current_usage" != "null" ]]; then
    # Get tokens from current_usage (includes cache)
    input_tokens=$(echo "$current_usage" | jq -r '.input_tokens // 0')
    cache_creation=$(echo "$current_usage" | jq -r '.cache_creation_input_tokens // 0')
    cache_read=$(echo "$current_usage" | jq -r '.cache_read_input_tokens // 0')

    # Total used from current request
    used_tokens=$((input_tokens + cache_creation + cache_read))

    # Free tokens (matching /context command display)
    free_tokens=$((total_size - used_tokens))

    # Calculate autocompact buffer for display only (22.5% of context window = 45k for 200k)
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

    # Calculate percentage with one decimal (relative to total size)
    free_pct=$(awk "BEGIN {printf \"%.1f\", ($free_tokens * 100.0 / $total_size)}")
    free_pct_int=${free_pct%.*}

    # Format tokens based on token_detail setting
    if [[ "$token_detail_enabled" == "true" ]]; then
        # Use awk for portable comma formatting (works regardless of locale)
        free_display=$(awk -v n="$free_tokens" 'BEGIN { printf "%\047d", n }')
    else
        free_display=$(awk "BEGIN {printf \"%.1fk\", $free_tokens / 1000}")
    fi

    # Color based on free percentage
    if [[ "$free_pct_int" -gt 50 ]]; then
        ctx_color="$GREEN"
    elif [[ "$free_pct_int" -gt 25 ]]; then
        ctx_color="$YELLOW"
    else
        ctx_color="$RED"
    fi

    context_info=" | ${ctx_color}${free_display} free (${free_pct}%)${RESET}"

    # Calculate and display token delta if enabled
    if [[ "$show_delta_enabled" == "true" ]]; then
        state_file=~/.claude/statusline.state
        has_prev=false
        prev_tokens=0
        if [[ -f "$state_file" ]]; then
            has_prev=true
            # Read last line to get previous token count
            prev_tokens=$(tail -1 "$state_file" 2>/dev/null | cut -d',' -f2)
            prev_tokens=${prev_tokens:-0}
        fi
        # Calculate delta
        delta=$((used_tokens - prev_tokens))
        # Only show positive delta (and skip first run when no previous state)
        if [[ "$has_prev" == "true" && "$delta" -gt 0 ]]; then
            if [[ "$token_detail_enabled" == "true" ]]; then
                delta_display=$(awk -v n="$delta" 'BEGIN { printf "%\047d", n }')
            else
                delta_display=$(awk "BEGIN {printf \"%.1fk\", $delta / 1000}")
            fi
            delta_info=" ${DIM}[+${delta_display}]${RESET}"
        fi
        # Append current usage with timestamp (format: timestamp,tokens)
        echo "$(date +%s),$used_tokens" >> "$state_file"
    fi
fi

# Output: [Model] directory | XXk free (XX%) [+delta] [AC]
echo -e "${DIM}[${model}]${RESET} ${BLUE}${dir_name}${RESET}${context_info}${delta_info}${ac_info}"
