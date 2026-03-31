# nix

nix-darwin + NixOS + Home Manager config.

## machines

| name | type | manage |
|------|------|--------|
| darwin | MacBook Pro (aarch64) | `just switch` |
| netty | NixOS VPS (x86_64) | `just switch-netty` |

## new machine setup

**darwin:**
```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
git clone https://github.com/harivansh-afk/nix.git ~/Documents/GitHub/nix
cd ~/Documents/GitHub/nix
sudo nix --extra-experimental-features 'nix-command flakes' run github:nix-darwin/nix-darwin/master#darwin-rebuild -- switch --flake path:.#darwin
exec zsh -l
bw login
export BW_SESSION="$(bw unlock --raw)"
just secrets-sync && just secrets-restore-files
exec zsh -l
```

**netty (from mac):**
```bash
nix run github:nix-community/nixos-anywhere -- --flake .#netty --target-host netty --build-on-remote
```

## secrets

SSH keys and credentials are stored in Bitwarden. After unlocking:
```bash
export BW_SESSION="$(bw unlock --raw)"
just secrets-sync          # shell env vars -> ~/.config/secrets/shell.zsh
just secrets-restore-files # SSH keys, AWS, GCloud, Codex, GitHub CLI
```

## dev

```bash
nix develop
just check
just fmt
```

## layout

```
hosts/darwin/        - macOS host entrypoint
hosts/netty/         - NixOS VPS entrypoint (disko + hardware + services)
modules/             - shared system modules + devshells
modules/hosts/       - flake-parts host output definitions
modules/nixpkgs.nix  - shared flake context (hosts, specialArgs, pkgs)
home/default.nix     - unified home entry (conditional on hostConfig)
home/common.nix      - modules shared across all hosts
home/xdg.nix         - XDG compliance (env vars, config files)
home/security.nix    - SSH/GPG permission enforcement
home/                - per-tool home-manager modules
lib/hosts.nix        - host metadata + feature flags
lib/theme.nix        - centralized color system (gruvbox)
lib/package-sets.nix - shared + host-gated package lists
config/              - repo-owned config files (nvim, tmux, etc.)
scripts/             - secret management and utility scripts
nix-maxxing.txt      - architecture and operations guide
```
