#!/usr/bin/env bash
set -uo pipefail

INPUT=$(cat)
cmd=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

deny() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

if [[ "$cmd" =~ ^grep([^a-zA-Z0-9_-]|$) ]]; then
  deny 'Use rg (ripgrep) instead of grep.'
fi
if [[ "$cmd" =~ (^|[^a-zA-Z0-9_/-])find([^a-zA-Z0-9_-]|$) ]]; then
  deny 'Use fd instead of find.'
fi
exit 0
