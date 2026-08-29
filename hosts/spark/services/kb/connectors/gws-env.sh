# shellcheck shell=bash
# Sourced by the gws connectors: OAuth client from the gws.env sops secret,
# token from the sops-managed credentials file (keyring-free under systemd).
set -a
. /run/secrets/gws.env 2>/dev/null || true
set +a
export GOOGLE_WORKSPACE_CLI_CLIENT_ID="${GWS_CLIENT_ID:-}"
export GOOGLE_WORKSPACE_CLI_CLIENT_SECRET="${GWS_CLIENT_SECRET:-}"
[ -r /run/secrets/gws-credentials.json ] &&
  export GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE=/run/secrets/gws-credentials.json
