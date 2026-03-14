# Nix Config

## Approach

This repo is the source of truth for the machine's reproducible developer
environment:

- `home/` contains the Home Manager modules for user-facing tools
- `config/` contains the repo-owned config trees copied from your daily setup
- `modules/` contains host-level `nix-darwin` policy and package layers
- `modules/homebrew.nix` is intentionally narrow and only exists for GUI apps
  that are still easier to keep in Brew on macOS
- `home/migration.nix` contains one-time ownership handoff logic from `~/dots`
  into Home Manager so the steady-state modules can stay focused on real config

## Layout

- `flake.nix`: top-level flake and host wiring
- `hosts/hari-macbook-pro/default.nix`: this machine's host config
- `modules/base.nix`: Nix settings and core packages
- `modules/macos.nix`: macOS defaults and host-level settings
- `modules/packages.nix`: system packages and fonts
- `modules/homebrew.nix`: the remaining Homebrew-managed GUI apps
- `home/`: Home Manager modules for shell, editor, CLI tools, and app config
- `home/migration.nix`: transitional cleanup for old `~/dots` symlinks
- `config/`: repo-owned config files consumed by Home Manager

## Ownership Boundaries

- Nix owns packages, dotfiles, shell/editor config, launchd services, and
  selected macOS defaults
- Homebrew is retained only for a narrow GUI cask boundary
- Keychain items, TCC/privacy permissions, browser history, and most
  `~/Library/Application Support` state are intentionally outside declarative
  Nix ownership

## Dedicated Inputs

Most tools come from `nixpkgs`. Fast-moving CLIs that you want to update on
their own cadence are pinned as dedicated flake inputs:

- `googleworkspace-cli`
- `claudeCode`

Bitwarden note:

- `bw` is installed via Homebrew as `bitwarden-cli`
- `bws` is not currently managed in this repo because I did not find a
  supported nixpkgs or Homebrew package for it on macOS during verification

## Commands

First switch:

```bash
nix run github:LnL7/nix-darwin/master#darwin-rebuild -- switch --flake .#hari-macbook-pro
```

After the first successful switch:

```bash
just switch
just build
just check
```

Update everything pinned by the flake:

```bash
nix flake update
just switch
```

Update only Codex or Claude:

```bash
nix flake lock --update-input claudeCode
just switch
```

Update Codex:

```bash
brew upgrade --cask codex
just switch
```

## What Still Needs Manual Handling

- Secrets and tokens under `~/.secrets`, `~/.npmrc`, `~/.config/gcloud`, `~/.config/gh`, and similar paths
- App state under `~/Library/Application Support`
- Anything that depends on local credentials, keychains, or encrypted stores
- Manual cleanup of old non-Nix installs that are no longer wanted

## Current Homebrew Scope

The current Homebrew boundary is only:

- `cap`
- `codex`
- `raycast`
- `riptide-dev`
- `thebrowsercompany-dia`
- `wispr-flow`

Homebrew activation is currently `cleanup = "uninstall"`, so anything outside
that list is treated as drift and removed on `darwin-rebuild switch`.
