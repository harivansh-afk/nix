#!/usr/bin/env bash
set -e

cd "$CLAUDE_PROJECT_DIR"

HOSTNAME=$(hostname -s)
echo "You are running on host: $HOSTNAME. Run commands locally - do NOT ssh to this host."

if git rev-parse --git-dir >/dev/null 2>&1; then
  echo "=== Recent commits ==="
  git log --oneline -10
fi
