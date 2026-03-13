# Nix Config

## Approach

The repo now owns the active shell/editor/tool config directly:

- `home/` contains the Home Manager modules for user-facing tools
- `config/` contains the repo-owned config trees copied from your daily setup
- `modules/homebrew.nix` is intentionally narrow and should keep shrinking over time
- Homebrew cleanup is still set to `"none"` so the first switch is non-destructive

## Layout

- `flake.nix`: top-level flake and host wiring
- `hosts/hari-macbook-pro/default.nix`: this machine's host config
- `modules/base.nix`: Nix settings and core packages
- `modules/macos.nix`: macOS defaults and host-level settings
- `modules/packages.nix`: system packages and fonts
- `modules/homebrew.nix`: the remaining Homebrew-managed apps and packages
- `home/`: Home Manager modules for shell, editor, CLI tools, and app config
- `config/`: repo-owned config files consumed by Home Manager

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

## What Still Needs Manual Work

- Secrets and tokens under `~/.secrets`, `~/.npmrc`, `~/.config/gcloud`, `~/.config/gh`, and similar paths
- Launch agents that are currently outside Nix
- App state under `~/Library/Application Support`
- Anything that depends on local credentials, keychains, or encrypted stores
- Deciding whether the remaining Homebrew entries should stay there or be eliminated
