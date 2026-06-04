# secrets

sops-nix secrets, encrypted with age keys derived from each host's ed25519 SSH
key. `registry.nix` is the single source of truth and carries the full inline
docs; this file is the quick reference.

## Layout

- `registry.nix` - declares every secret and its options (owner, mode,
  `restartUnits`, `exposeToShell`, etc.). Consumed by
  `modules/security/sops.nix` and `home/zsh.nix`.
- `user/<name>` - per-admin-user secrets, decrypted on every host the admin's
  SSH key is a recipient for. Auto-sourced into interactive zsh unless
  `exposeToShell = false`.
- `hosts/<host>/<name>` - host-bound secrets, decrypted only on that host.

Recipient routing lives in `.sops.yaml` (path regex per host / per user). See
`AGENTS.md` "Secrets" for the recipient anchors and the `barrett-` prefix rule.

## Add a secret

1. Drop the file in the matching directory:
   - `secrets/user/<name>` for user-shell secrets
   - `secrets/hosts/<host>/<name>` for host-bound secrets

   `.sops.yaml` picks the recipient set automatically.
2. Add a one-line entry in `registry.nix`.
3. Consume via `config.sops.secrets."<name>".path`.

## Edit a secret

```
just sops-edit secrets/hosts/spark/<file>
```
