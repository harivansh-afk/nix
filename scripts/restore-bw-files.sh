#!/usr/bin/env bash
set -euo pipefail
export NODE_NO_WARNINGS=1

if ! command -v bw >/dev/null 2>&1; then
  echo "bw is not installed" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is not installed" >&2
  exit 1
fi

if [[ "${BW_SESSION:-}" == "" ]]; then
  echo 'BW_SESSION is not set. Run: export BW_SESSION="$(bw unlock --raw)"' >&2
  exit 1
fi

timestamp="$(date +%Y%m%d-%H%M%S)"

read_note() {
  local item_name="$1"
  local item_id
  item_id="$(bw list items --session "${BW_SESSION}" | jq -r --arg n "${item_name}" '.[] | select(.name == $n) | .id' | head -1)"
  if [[ -z "${item_id}" ]]; then
    echo "Bitwarden item not found: ${item_name}" >&2
    exit 1
  fi
  bw get item "${item_id}" --session "${BW_SESSION}" | jq -r '.notes'
}

backup_if_exists() {
  local target="$1"
  if [[ -e "${target}" || -L "${target}" ]]; then
    mv "${target}" "${target}.bw-bak-${timestamp}"
  fi
}

write_file() {
  local target="$1"
  local mode="$2"
  local content="$3"
  mkdir -p "$(dirname "${target}")"
  backup_if_exists "${target}"
  printf '%s' "${content}" > "${target}"
  chmod "${mode}" "${target}"
  printf 'restored %s\n' "${target}"
}

restore_plain_note() {
  local item_name="$1"
  local target="$2"
  local mode="$3"
  write_file "${target}" "${mode}" "$(read_note "${item_name}")"
}

restore_aws_credentials() {
  local note
  local access_key
  local secret_key
  note="$(read_note 'Machine: AWS Default Credentials')"
  access_key="$(printf '%s\n' "${note}" | sed -n 's/^aws_access_key_id=//p' | head -1)"
  secret_key="$(printf '%s\n' "${note}" | sed -n 's/^aws_secret_access_key=//p' | head -1)"

  local aws_creds="${AWS_SHARED_CREDENTIALS_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/aws/credentials}"
  write_file "${aws_creds}" 600 "[default]
aws_access_key_id = ${access_key}
aws_secret_access_key = ${secret_key}
"
}

restore_gcloud_adc() {
  local note
  note="$(read_note 'Machine: GCloud ADC')"

  local account
  local client_id
  local client_secret
  local quota_project_id
  local refresh_token
  local type
  local universe_domain

  account="$(printf '%s\n' "${note}" | sed -n 's/^account=//p' | head -1)"
  client_id="$(printf '%s\n' "${note}" | sed -n 's/^client_id=//p' | head -1)"
  client_secret="$(printf '%s\n' "${note}" | sed -n 's/^client_secret=//p' | head -1)"
  quota_project_id="$(printf '%s\n' "${note}" | sed -n 's/^quota_project_id=//p' | head -1)"
  refresh_token="$(printf '%s\n' "${note}" | sed -n 's/^refresh_token=//p' | head -1)"
  type="$(printf '%s\n' "${note}" | sed -n 's/^type=//p' | head -1)"
  universe_domain="$(printf '%s\n' "${note}" | sed -n 's/^universe_domain=//p' | head -1)"

  local json
  json="$(
    jq -n \
      --arg account "${account}" \
      --arg client_id "${client_id}" \
      --arg client_secret "${client_secret}" \
      --arg quota_project_id "${quota_project_id}" \
      --arg refresh_token "${refresh_token}" \
      --arg type "${type}" \
      --arg universe_domain "${universe_domain}" \
      '{
        account: $account,
        client_id: $client_id,
        client_secret: $client_secret,
        quota_project_id: $quota_project_id,
        refresh_token: $refresh_token,
        type: $type,
        universe_domain: $universe_domain
      }'
  )"

  write_file "${HOME}/.config/gcloud/application_default_credentials.json" 600 "${json}"
}

restore_ssh_key() {
  local item_name="$1"
  local rel_path="$2"
  local item_json
  local private_key
  local public_key

  item_json="$(bw list items --session "${BW_SESSION}" | jq -r --arg n "${item_name}" '.[] | select(.name == $n)')"
  if [[ -z "${item_json}" ]]; then
    echo "Bitwarden item not found: ${item_name}" >&2
    exit 1
  fi

  private_key="$(printf '%s' "${item_json}" | jq -r '.sshKey.privateKey')"
  public_key="$(printf '%s' "${item_json}" | jq -r '.sshKey.publicKey')"

  write_file "${HOME}/.ssh/${rel_path}" 600 "${private_key}"
  if [[ -n "${public_key}" && "${public_key}" != "null" ]]; then
    write_file "${HOME}/.ssh/${rel_path}.pub" 644 "${public_key}"
  fi
}

restore_ssh_key 'SSH Key - id_ed25519' 'id_ed25519'

restore_aws_credentials
restore_gcloud_adc
restore_plain_note 'Machine: Codex Auth' "${HOME}/.codex/auth.json" 600
if [[ "$(uname)" == "Darwin" ]]; then
  restore_plain_note 'Machine: Vercel Auth' "${HOME}/Library/Application Support/com.vercel.cli/auth.json" 600
fi

# GitHub CLI auth
if command -v gh >/dev/null 2>&1; then
  read_note 'Machine: GitHub Token' | gh auth login --with-token
  printf 'restored gh auth\n'
fi
