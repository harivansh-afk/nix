# secrets

sops-nix secrets, encrypted for the age keys in `.sops.yaml` (derived from
the admin's and each host's ed25519 SSH key). `registry.nix` declares every
secret and its options; `modules/security/sops.nix` turns it into
`sops.secrets`.

- `user/<name>`: decrypts on every host the admin key reaches. `KEY=value`
  files are named `.env` and sourced into interactive zsh; raw tokens have no
  extension and set `exposeToShell = false`.
- `hosts/<host>/<name>`: decrypts on that host only.

Add a secret: put the file in the matching directory, add its entry to
`registry.nix`, consume `config.sops.secrets."<name>".path`. Edit one with
`just sops-edit secrets/<dir>/<name>`.

## Heroku UVA login

`user/heroku-uva.json` stores the account name, email, password, login URL, and MFA authenticator URI as
one SOPS-encrypted JSON payload. It uses the existing `admin_macbook` and
`host_spark` recipients. The registry gives `rathi` a mode-0400 file at
`/run/secrets/heroku-uva.json` after the normal host rebuild; it is not sourced
into the shell or exported into the environment.

To read the login on a machine with an authorized age identity:

```sh
nix run nixpkgs#sops -- decrypt --input-type binary --output-type binary secrets/user/heroku-uva.json
```

For the MacBook SSH identity, set
`SOPS_AGE_SSH_PRIVATE_KEY_FILE=$HOME/.ssh/id_ed25519` when running SOPS.
To rotate the password, update Heroku first, then edit the encrypted payload:

```sh
nix run nixpkgs#sops -- edit --input-type binary --output-type binary secrets/user/heroku-uva.json
```
The `totp_uri` field contains the authenticator setup secret. Import it into an
authenticator app on your own device; treat it with the same care as the password.

Commit the ciphertext and rebuild the hosts that need the updated login.
Never stage a decrypted copy or put the password in a PR description.
