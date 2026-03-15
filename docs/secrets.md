# Secrets

## Current Model

This repo does not store secret values in Nix.

Instead:

- Bitwarden vault items are the current source of truth for imported machine
  secrets
- Nix/Home Manager owns the integration points
- generated runtime files live outside the repo under `~/.config/secrets`

That boundary matters because the Nix store is not the right place for real
secret values.

## What Is Already Wired

- [home/zsh.nix](/Users/rathi/Documents/GitHub/nix/home/zsh.nix) sources
  `~/.config/secrets/shell.zsh` when present
- [scripts/render-bw-shell-secrets.sh](/Users/rathi/Documents/GitHub/nix/scripts/render-bw-shell-secrets.sh)
  renders that file from Bitwarden vault items
- [scripts/restore-bw-files.sh](/Users/rathi/Documents/GitHub/nix/scripts/restore-bw-files.sh)
  restores file-based credentials and SSH material from Bitwarden vault items
- [justfile](/Users/rathi/Documents/GitHub/nix/justfile) exposes this as
  `just secrets-sync` and `just secrets-restore-files`

## Daily Shell Flow

```bash
export BW_SESSION="$(bw unlock --raw)"
just secrets-sync
exec zsh -l
```

That flow currently materializes:

- `OPENAI_API_KEY`
- `GREPTILE_API_KEY`
- `CONTEXT7_API_KEY`
- `MISTRAL_API_KEY`

## Machine Secret Coverage

The Bitwarden vault now holds:

- API keys and CLI tokens
- AWS default credentials
- GCloud ADC
- Stripe CLI config
- Codex auth
- Vercel auth
- SSH configs
- SSH private keys

The vault is currently the backup/recovery source of truth for those values.

## Sandbox Strategy

For a fresh sandbox or new machine, the clean bootstrap is:

1. `darwin-rebuild switch` or Home Manager activation
2. authenticate `bw`
3. `just secrets-sync`
4. `just secrets-restore-files`

That gives you a usable dev shell quickly without committing any secret values
into the repo.

## Future Upgrade

If you want fully non-interactive sandbox secret injection, the next step is to
move the env-style secrets from normal Bitwarden vault items into Bitwarden
Secrets Manager (`bws`) and keep file-based credentials and SSH material in the
normal vault.

That would give you:

- `bws` for machine/app secrets
- `bw` for human-managed vault items, SSH material, and recovery data
