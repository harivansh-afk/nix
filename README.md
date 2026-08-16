# Nix

This repo is the home for all my configs and creations.

Everything is a single flake, declared with [flake-parts](https://github.com/hercules-ci/flake-parts) and managed by [Determinate Nix](https://docs.determinate.systems/determinate-nix/).

## Tour

**`dots/`**

- plain-file configs for ~28 tools: ghostty, zsh, git, lazygit, and more
- no home-manager: an activation script symlinks them into place
- my links point at the live checkout, so edits apply without a rebuild

**`dots/nvim/`**

- `mux` - sessions, panes, and windows inside Neovim: one headless server per project, thin clients, persistence across reboots
- `pr` - code review inside Neovim: PR list, file tree, review marks, CI status, `pr://` buffers

**`modules/services/`**

- [Forgejo](https://git.harivan.sh) - my git
- llama.cpp - local model inference
- Whisper Large v3 - for speech-to-text using voice-ink
- Hermes Agent - yes
- Cognee KB - central knowledge graph with relational search capabilities
- Vaultwarden - password manager

**`lib/theme.nix`**

- [cozybox.nvim](https://git.harivan.sh/harivansh-afk/cozybox.nvim) is my custom palette for all my software

**`packages.nix`**

- one shared package set for both machines
- only truly macOS-specific things stay on Homebrew, rest is nix


## Spark

My NixOS workstation ( NVIDIA DGX Spark [GB10, aarch64-linux])

- friends who want access get a user definition in `users/`
- NVIDIA kernel, drivers, and container support come from the upstream [nixos-dgx-spark](https://github.com/graham33/nixos-dgx-spark) module
- disks declared with [disko](https://github.com/nix-community/disko); from-scratch provisioning via [nixos-anywhere](https://github.com/nix-community/nixos-anywhere)

## Structure

```
flake.nix            entrypoint - inputs and outputs
flake/               host assembly, devshell, args
lib/                 host metadata, theme palette
inventory/           typed host inventory via evalModules
hosts/               per-host config
  macbook/
  spark/
  ix/
users/               multi-user definitions for spark
dots/                app configs symlinked into XDG paths (live-editable)
  nvim/              the Neovim setup: mux, pr, statusline
  ...                one directory per tool
modules/             reusable modules
  apps/              voiceink
  security/          sops, user isolation
  services/          forgejo, inference, whisper, hermes, kb-*, caddy, ...
  users/             shared dotfile and user setup
system/              shared system-level config
packages.nix         shared package sets (core, extras, darwin)
scripts/             runtime helpers (mux, ghpr, iosrun, theme, ...)
secrets/             sops-encrypted secrets per host
terraform/           declarative Cloudflare DNS via terranix
assets/              readme artwork
```
