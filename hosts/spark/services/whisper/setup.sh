#!/usr/bin/env bash
# Runtime uv venv: torch nightly cu130 for aarch64 is not in nixpkgs.
# Inputs from the unit: STATE_DIR, VENV, PYTHON, SERVER_PY, REQ_VERSION.
set -euo pipefail
install -m0644 "$SERVER_PY" "$STATE_DIR/server.py"
if [ "$(cat "$STATE_DIR/.req-version" 2>/dev/null || true)" != "$REQ_VERSION" ] || [ ! -x "$VENV/bin/python" ]; then
  uv venv --python "$PYTHON" "$VENV"
  uv pip install --python "$VENV/bin/python" --prerelease=allow \
    --index-url https://download.pytorch.org/whl/nightly/cu130 torch
  uv pip install --python "$VENV/bin/python" \
    'transformers==5.9.0' accelerate soundfile librosa numpy \
    fastapi 'uvicorn[standard]' python-multipart huggingface_hub
  printf '%s' "$REQ_VERSION" >"$STATE_DIR/.req-version"
fi
