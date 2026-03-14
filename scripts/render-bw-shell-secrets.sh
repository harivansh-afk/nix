#!/usr/bin/env bash
set -euo pipefail

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

out_dir="${HOME}/.config/secrets"
out_file="${out_dir}/shell.zsh"
tmp_file="$(mktemp)"

mkdir -p "${out_dir}"

read_note() {
  local item_name="$1"
  bw get item "${item_name}" --session "${BW_SESSION}" | jq -r '.notes'
}

extract_env_value() {
  local item_name="$1"
  local var_name="$2"
  read_note "${item_name}" | sed -n "s/^${var_name}=//p" | head -1
}

cat > "${tmp_file}" <<'EOF'
# Generated from Bitwarden. Do not edit by hand.
EOF

append_export_from_note() {
  local var_name="$1"
  local item_name="$2"
  local value
  value="$(read_note "${item_name}")"
  printf 'export %s=%q\n' "${var_name}" "${value}" >> "${tmp_file}"
}

append_export_from_env_note() {
  local var_name="$1"
  local item_name="$2"
  local value
  value="$(extract_env_value "${item_name}" "${var_name}")"
  printf 'export %s=%q\n' "${var_name}" "${value}" >> "${tmp_file}"
}

append_export_from_note "OPENAI_API_KEY" "Machine: OpenAI API Key"
append_export_from_note "GREPTILE_API_KEY" "Machine: Greptile API Key"
append_export_from_note "CONTEXT7_API_KEY" "Machine: Context7 API Key"
append_export_from_env_note "MISTRAL_API_KEY" "Machine: Vibe Env"

chmod 600 "${tmp_file}"
mv "${tmp_file}" "${out_file}"

printf 'Wrote %s\n' "${out_file}"
