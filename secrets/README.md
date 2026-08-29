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
