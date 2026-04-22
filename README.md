# Nix Leveraging

Single dependency graph that owns my macOS computer and my linux workstation

Using [determinate nix](https://docs.determinate.systems/determinate-nix/) for
parallel builds and better ux

macbook — nix-darwin + home-manager + nix-homebrew

netty — nixosSystem + disko + home-manager

Home Manager is the userland control plane: 
Rust, Go, Node, Python, AWS, and friends are routed into XDG paths; 

SSH and GPG perms are locked on every activation. 

A migration module handles the cutover from legacy symlinks.

[cozybox.nvim](https://github.com/harivansh-afk/cozybox.nvim) drives Ghostty, tmux, fzf, zsh syntax highlighting, bat, and delta, with a generated script to hot-swap light/dark. 

configs are repo-owned (dots) rather than scattered across $HOME. 

Global agent skills install declaratively.

Secrets live in self-hosted Bitwarden and render at activation time.

Deploy with `just switch` (laptop) or `just switch-netty` (server).

The KVM is a declarative service bundle — only `22/80/443` exposed; everything else listens on `127.0.0.1` behind nginx + ACME:

- Forgejo mirroring to GitHub — `git.harivan.sh`
- Vaultwarden — `vault.harivan.sh`
- betterNAS control plane + node agent — `api.betternas.com`
- Hermes agent — `netty.harivan.sh`
- Delta — `delta.harivan.sh`

## Structure

```
flake.nix        inputs, outputs, per-host system assembly
justfile         switch, switch-netty, fmt, ci entry points
packages.nix     shared package set consumed by hosts
flake/           per-host assembly (macbook, netty, devshell, args)
lib/             host metadata + central theme palette
hosts/           host roots (macbook/, netty/ with services/)
system/          shared system-level nix config and packages
home/            home-manager modules, one file per tool
dots/            repo-owned app configs (symlinked into XDG)
scripts/         runtime scripts wired via home/scripts.nix
.forgejo/        CI workflows
```
