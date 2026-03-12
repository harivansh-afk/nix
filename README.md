# Rathi's Nix Config

This repo is the start of a full-machine macOS setup built with:

- `nix-darwin` for system settings
- `home-manager` for home directory files
- `nix-homebrew` plus `homebrew.*` for the large set of macOS packages and casks that still make sense to manage through Homebrew

The friend config under `tmp/dots` is kept here as reference material only. The config in this repo is your own scaffold.

## Current approach

The migration is intentionally conservative:

- Homebrew inventory is captured declaratively in [`modules/homebrew.nix`](./modules/homebrew.nix).
- Your live dotfiles stay the source of truth for now via out-of-store symlinks from [`home/dotfiles.nix`](./home/dotfiles.nix).
- Cleanup is set to `"none"` so the first switch does not delete anything you forgot to inventory.

That gives you a reproducible baseline without forcing a risky rewrite of shell/editor configs on day one.

## Layout

- `flake.nix`: top-level flake and host wiring
- `hosts/hari-macbook-pro/default.nix`: this machine's host config
- `modules/base.nix`: Nix settings and core packages
- `modules/macos.nix`: macOS defaults and host-level settings
- `modules/homebrew.nix`: taps, brews, and casks from the current machine
- `home/dotfiles.nix`: Home Manager symlinks into `~/dots`
- `docs/machine-audit.md`: inventory and migration notes from the current box

## Commands

Bootstrap the host:

```bash
nix run github:LnL7/nix-darwin/master#darwin-rebuild -- switch --flake .#hari-macbook-pro
```

After the first successful switch:

```bash
just switch
just build
just check
```

Capture a fresh machine inventory before any destructive changes:

```bash
./scripts/snapshot-machine.sh
```

## What Still Needs Manual Work

- Secrets and tokens under `~/.secrets`, `~/.npmrc`, `~/.config/gcloud`, `~/.config/gh`, and similar paths
- Launch agents that are currently outside Nix
- App state under `~/Library/Application Support`
- Apps installed outside Homebrew casks or the App Store
- Translating raw files from `~/dots` into pure Home Manager modules over time

The snapshot script writes raw inventories under `inventory/current/` so you can diff the machine state over time instead of relying on memory.

## Important Note About Dotfiles

Your live machine currently points at `~/dots`, not `~/Documents/GitHub/dots`. This config follows the live machine and expects `~/dots` to exist.
