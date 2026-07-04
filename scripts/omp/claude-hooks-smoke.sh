#!/usr/bin/env bash
# Smoke test for the Claude hook protocol bridge (dots/omp/extensions/claude-hooks.ts).
#
# Run this when bumping the omp pin in flake/omp.nix: it catches extension-API
# drift before the new binary ships. Needs a working `omp` with model
# credentials (real -p runs), so it is a manual/CI gate, not a nix check.
#
#   OMP=/path/to/omp scripts/omp/claude-hooks-smoke.sh   # override binary
#
# Asserts three Claude hook protocol paths end to end:
#   1. SessionStart plain-stdout + JSON additionalContext -> model-visible context
#   2. PreToolUse JSON permissionDecision=deny            -> tool blocked, reason verbatim
#   3. PreToolUse exit 2                                  -> tool blocked, stderr verbatim
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BRIDGE="$REPO_ROOT/dots/omp/extensions/claude-hooks.ts"
OMP_BIN="${OMP:-omp}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fx="$work/fixture"
mkdir -p "$fx/.claude/hooks"
git init -q "$fx"

# Empty user-level Claude config: only fixture project hooks fire, on any machine.
user_dir="$work/claude-user"
mkdir -p "$user_dir"

cat >"$fx/.claude/hooks/session-start.sh" <<'EOF'
#!/usr/bin/env bash
echo "HOOKMARK-ALPHA-7291: injected by fixture SessionStart hook"
EOF

cat >"$fx/.claude/hooks/session-id.sh" <<'EOF'
#!/usr/bin/env bash
sid=$(jq -r '.session_id')
echo "{\"hookSpecificOutput\": {\"hookEventName\": \"SessionStart\", \"additionalContext\": \"HOOKMARK-SESSION-ID: $sid\"}}"
EOF

cat >"$fx/.claude/hooks/deny-marker.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
cmd=$(jq -r '.tool_input.command // empty')
if [[ "$cmd" == *MARKER_FORBIDDEN* ]]; then
  jq -n '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: "HOOKDENY-BETA-4455: forbidden marker command"}}'
fi
exit 0
EOF

cat >"$fx/.claude/hooks/exit2-marker.sh" <<'EOF'
#!/usr/bin/env bash
cmd=$(jq -r '.tool_input.command // empty')
if [[ "$cmd" == *MARKER_EXITTWO* ]]; then
  echo "HOOKDENY-GAMMA-8812: blocked via exit 2" >&2
  exit 2
fi
exit 0
EOF

chmod +x "$fx"/.claude/hooks/*.sh

cat >"$fx/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "SessionStart": [
      { "hooks": [{ "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/session-start.sh" }] },
      { "hooks": [{ "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/session-id.sh", "timeout": 5 }] }
    ],
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [{ "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/deny-marker.sh" }] },
      { "matcher": "Bash", "hooks": [{ "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/exit2-marker.sh" }] }
    ]
  }
}
EOF

# Do NOT use --no-extensions here: despite its help text it also drops explicit
# -e paths (oh-my-pi main.ts, noExtensions clears additionalExtensionPaths).
# Instead, pass -e only when the activation symlink is not already loading this
# exact file, so the bridge never registers twice (double hook execution).
extra_args=()
installed="$HOME/.omp/agent/extensions/claude-hooks.ts"
if [ ! -e "$installed" ] || [ "$(readlink -f "$installed")" != "$(readlink -f "$BRIDGE")" ]; then
  extra_args=(-e "$BRIDGE")
fi

run_omp() {
  (cd "$fx" && CLAUDE_CONFIG_DIR="$user_dir" "$OMP_BIN" -p --no-session ${extra_args[0]+"${extra_args[@]}"} "$1")
}

fail() {
  echo "FAIL: $1" >&2
  echo "--- output ---" >&2
  echo "$2" >&2
  exit 1
}

echo "[1/3] SessionStart context injection"
out=$(run_omp "List every line in your context that contains the string HOOKMARK. Quote each verbatim. Do not use any tools.")
grep -q "HOOKMARK-ALPHA-7291" <<<"$out" || fail "plain-stdout SessionStart context missing" "$out"
grep -q "HOOKMARK-SESSION-ID" <<<"$out" || fail "JSON additionalContext missing" "$out"

echo "[2/3] PreToolUse JSON deny"
out=$(run_omp "Run this exact bash command: echo MARKER_FORBIDDEN. If the tool call fails, quote the full error text verbatim and stop.")
grep -q "HOOKDENY-BETA-4455" <<<"$out" || fail "permissionDecision deny not enforced" "$out"

echo "[3/3] PreToolUse exit-2 deny"
out=$(run_omp "Run this exact bash command: echo MARKER_EXITTWO. If the tool call fails, quote the full error text verbatim and stop.")
grep -q "HOOKDENY-GAMMA-8812" <<<"$out" || fail "exit-2 block not enforced" "$out"

echo "PASS: claude-hooks bridge smoke (3/3)"
