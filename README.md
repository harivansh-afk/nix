# Nix Leveraging

Single dependency graph for my macOS laptop.

Using [determinate nix](https://docs.determinate.systems/determinate-nix/) for
parallel builds and better ux.

macbook — nix-darwin + home-manager + nix-homebrew

Home Manager is the userland control plane:
Rust, Go, Node, Python, AWS, and friends are routed into XDG paths;

SSH and GPG perms are locked on every activation.

A migration module handles the cutover from legacy symlinks.

[cozybox.nvim](https://github.com/harivansh-afk/cozybox.nvim) drives Ghostty, tmux, fzf, zsh syntax highlighting, bat, and delta, with a generated script to hot-swap light/dark.

configs are repo-owned (dots) rather than scattered across $HOME.

Global agent skills install declaratively.

Secrets live in self-hosted Bitwarden and render at activation time.

Deploy with `just switch`.

The workstation (`spark`, NVIDIA DGX running Ubuntu) is managed separately
from this flake — plain docker-compose + systemd units + Caddy for ingress.
Its configuration lives alongside the host in a future `spark/` subdirectory.

## Structure

```
flake.nix        inputs, outputs, per-host system assembly
justfile         switch, fmt, ci entry points
packages.nix     shared package set consumed by hosts
flake/           per-host assembly (macbook, devshell, args)
lib/             host metadata + central theme palette
hosts/           host roots (macbook/)
system/          shared system-level nix config and packages
home/            home-manager modules, one file per tool
dots/            repo-owned app configs (symlinked into XDG)
scripts/         runtime scripts wired via home/scripts.nix
.forgejo/        CI workflows
```
