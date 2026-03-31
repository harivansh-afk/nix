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

The VPS has a declarative service bundle: 
- static networking
- nginx with ACME
- Forgejo mirroring to GitHub
- sandbox agent behind a CORS proxy
- bounded GC and journald retention
