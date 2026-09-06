#!/usr/bin/env bash
# Runtime uv venv: yt-dlp extractor fixes ship weekly and must not wait on a
# nixpkgs bump. Bump reqVersion in default.nix when changing these pins.
set -euo pipefail
install -m0644 "$APP_PY" "$STATE_DIR/main.py"
install -m0644 "$AUTH_PY" "$STATE_DIR/auth.py"
if [ "$(cat "$STATE_DIR/.req-version" 2>/dev/null || true)" != "$REQ_VERSION" ] || [ ! -x "$VENV/bin/python" ]; then
  uv venv --python "$PYTHON" "$VENV"
  uv pip install --python "$VENV/bin/python" \
    'fastapi==0.115.0' 'uvicorn==0.30.0' 'yt-dlp==2026.8.19' 'requests==2.32.5' 'PyJWT[crypto]==2.13.0'
  printf '%s' "$REQ_VERSION" >"$STATE_DIR/.req-version"
fi
