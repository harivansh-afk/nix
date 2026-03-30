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
hosts/darwin/   - macOS host entrypoint
hosts/netty/    - NixOS VPS entrypoint (disko + hardware)
modules/        - shared system modules + devshells
home/           - Home Manager modules
lib/hosts.nix   - host metadata used by the flake
lib/            - shared package sets and theme system
config/         - repo-owned config files (nvim, tmux, etc.)
scripts/        - secret management and utility scripts
```
