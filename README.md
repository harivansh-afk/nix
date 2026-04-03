# Nix Leveraging

Single dependency graph that owns a macOs laptop and a Linux KVM. 
Both collapse into the same reproducible interface. 

The darwin host composes nix-darwin, home-manager, and nix-homebrew. 
The netty host composes nixosSystem, disko, and home-manager. 

Global username, per-host metadata and feature flags are encoded as data so leaf modules never need ad hoc platform checks.

The machine surface is split into core, extras, and fonts.

claude-code-nix, neovim-nightly, disko, and nix-homebrew are pinned in the flake

Home Manager is the userland control plane. 
Rust, Go, Node, Python, AWS, and some other tools are routed into XDG-compliant paths. 
SSH and GPG permissions are locked down on every activation. 

A migration module handles the cutover from legacy symlinks so nothing is left to clean up manually.

A single palette drives colors for Ghostty, tmux, fzf, zsh syntax highlighting, bat, and delta.
A generated theme script hot-swaps light and dark across all of them. 

Tool configs are repo-owned rather than scattered across $HOME.
Global agent skills are installed declaratively using skills.sh and only resync when the manifest hash changes.

Secrets live in Bitwarden and are rendered at activation time using cli
Deployment is `just switch` for the laptop and `just switch-netty` for the server.

All PRs auto-merge on creation if tests pass

The KVM has a declarative service bundle: 
- netty exposes 3 tcp ports (22:ssh, 80:http, 443:https)
- services only listen on 127.0.0.1 (runs behind nginx with ACME)
- Self hosts Forgejo mirroring to GitHub (git.harivan.sh)
- Self hosts VaultWarden
- betterNAS control-plane and node agent (api.betternas.com)
- OpenClaw gateway behind nginx (netty.harivan.sh)
