#!/usr/bin/env bash
# Runs after the NixOS module's own preStart, as the git user.
#
# Forgejo 16 does not consult credential.helper for pull-mirror fetches, so
# the GitHub token is embedded into every github.com mirror remote on each
# start; rotating the secret propagates on the next restart.
#
# Environment: GITHUB_TOKEN_FILE, GIT_CREDENTIAL_FILE, FORGEJO (binary),
# OAUTH_SOURCES (lines of name:provider:credential:id_var:secret_var),
# CREDENTIALS_DIRECTORY (systemd).
set -euo pipefail

# shellcheck disable=SC1090
. "$GITHUB_TOKEN_FILE"
printf 'https://oauth2:%s@github.com\n' "$GITHUB_TOKEN" >"$GIT_CREDENTIAL_FILE"
chmod 600 "$GIT_CREDENTIAL_FILE"

for repo in /var/lib/forgejo/repositories/*/*.git; do
  [ -d "$repo" ] || continue
  url=$(git -C "$repo" config remote.origin.url 2>/dev/null) || continue
  case "$url" in
  https://github.com/*) path="${url#https://github.com/}" ;;
  https://*@github.com/*) path="${url#https://*@github.com/}" ;;
  *) continue ;;
  esac
  git -C "$repo" config remote.origin.url "https://oauth2:$GITHUB_TOKEN@github.com/$path"
done

export FORGEJO_WORK_DIR=/var/lib/forgejo
export FORGEJO_CUSTOM=/var/lib/forgejo/custom
config=/var/lib/forgejo/custom/conf/app.ini

credential_value() {
  set -a
  # shellcheck disable=SC1090
  . "$CREDENTIALS_DIRECTORY/$1"
  set +a
  printenv "$2"
}

while IFS=: read -r name provider credential id_var secret_var; do
  [ -n "$name" ] || continue
  client_id="$(credential_value "$credential" "$id_var")"
  client_secret="$(credential_value "$credential" "$secret_var")"
  if [ -z "$client_id" ] || [ -z "$client_secret" ]; then
    echo "Missing OAuth credentials for $name" >&2
    exit 1
  fi
  existing_id="$("$FORGEJO" -c "$config" admin auth list |
    awk -F '\t' -v name="$name" 'NR>1 && $2==name {print $1; exit}')"
  if [ -z "$existing_id" ]; then
    "$FORGEJO" -c "$config" admin auth add-oauth \
      --provider "$provider" --name "$name" --key "$client_id" --secret "$client_secret"
    echo "Added OAuth source $name"
  else
    "$FORGEJO" -c "$config" admin auth update-oauth \
      --provider "$provider" --id "$existing_id" --name "$name" --key "$client_id" --secret "$client_secret"
    echo "Updated OAuth source $name (id=$existing_id)"
  fi
done <<<"$OAUTH_SOURCES"
