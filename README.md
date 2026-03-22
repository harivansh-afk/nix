# Nix Config

## Layout

- `flake.nix`: top-level flake and host wiring
- `hosts/darwin/default.nix`: macOS nix-darwin host config
- `hosts/linux/default.nix`: standalone Linux Home Manager host config
- `modules/base.nix`: Nix settings and core packages
- `modules/macos.nix`: macOS defaults and host-level settings
- `modules/packages.nix`: system packages and fonts
- `modules/homebrew.nix`: the remaining Homebrew-managed GUI apps
- `home/`: Home Manager modules for shell, editor, CLI tools, and app config
- `home/common.nix`: shared Home Manager imports used by macOS and Linux
- `home/linux.nix`: Linux Home Manager entrypoint
- `home/migration.nix`: transitional cleanup for old `~/dots` symlinks
- `config/`: repo-owned config files consumed by Home Manager

## Ownership Boundaries

- Nix owns packages, dotfiles, shell/editor config, launchd services, and
  selected macOS defaults
- Homebrew is retained only for a narrow GUI cask boundary
- Keychain items, TCC/privacy permissions, browser history, and most
  `~/Library/Application Support` state are intentionally outside declarative
  Nix ownership

## Bitwarden note:

- `bw` is installed via Homebrew as `bitwarden-cli`
- `bws` is not currently managed in this repo because I did not find a
  supported nixpkgs or Homebrew package for it on macOS during verification
- daily shell secrets are synced from Bitwarden into `~/.config/secrets/shell.zsh`
  via `just secrets-sync`
- vault items are currently the source of truth for imported machine secrets and
  SSH material
