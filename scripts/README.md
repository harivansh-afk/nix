# scripts

Runtime scripts for the flake. Two categories: scripts packaged into the
environment via `default.nix`, and scripts run by hand.

## Packaged scripts (wired)

`default.nix` builds these with `pkgs.writeShellApplication` and exposes them as
`commonPackages`. `modules/users/user-config.nix` adds them to each user's
packages, so they land on `PATH` on every host. Sources live in `bin/`.

| Command        | Source                | Purpose                                      |
|----------------|-----------------------|----------------------------------------------|
| `theme`        | `bin/theme.sh`        | Switch cozybox dark/light, relink theme assets |
| `wallpaper-gen`| `bin/wallpaper-gen.sh`| Generate themed wallpapers (uses `lib/wallpaper-gen.py`) |

`default.nix` also exports `themeAssetsText` and `tmuxConfigs`, consumed by the
theme-activation block in `modules/users/user-config.nix`.

> `ga`, `ghpr`, and `iosrun` moved to `packages/bash-macros/` (the registry).
> `theme` and `wallpaper-gen` stay here until the theme-activation coupling is
> untangled in a later pass.

## Helpers (`lib/`)

Not standalone commands. Referenced by other config:

- `wallpaper-gen.py` - Python backing the `wallpaper-gen` command.

## Run-by-hand scripts (`forgejo-mirror/`)

Not wired into any package or unit. Run manually as documented in `AGENTS.md`:

- `reconcile.sh` - reconcile forgejo push-mirrors against
  `/etc/forgejo-mirror/manifest.json`. Run as root.
- `github-ux.sh` - apply GitHub-side metadata/banners to push-mirrors. Run on demand.
- `avatar-backfill.sh` - backfill Forgejo mirror-owner org avatars from GitHub. Dry-run by default; use `--apply` to write through the Forgejo API.

## Adding a packaged script

1. Drop the source in `bin/`.
2. Add an `mkScript` entry to `commonPackages` (or `darwinPackages` /
   `linuxPackages`) in `default.nix`.
