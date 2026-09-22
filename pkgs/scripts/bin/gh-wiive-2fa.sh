# gh-wiive-2fa - print the current TOTP code for the shared eng-wiive
# GitHub account. The base32 secret is the sops secret `gh-wiive-totp`
# (secrets/user/gh-wiive-totp), decrypted to /run/secrets on every host
# the admin key reaches.
secret_file="${GH_WIIVE_TOTP_FILE:-/run/secrets/gh-wiive-totp}"

if [ ! -r "$secret_file" ]; then
  echo "gh-wiive-2fa: cannot read $secret_file (rebuild with the sops secret declared?)" >&2
  exit 1
fi

oathtool --totp -b "$(tr -d '[:space:]' <"$secret_file")"
