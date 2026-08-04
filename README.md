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
- a custom statusline, git stats, and live theme switching

**`modules/services/`**

- [Forgejo](https://git.harivan.sh) - the canonical forge, with Actions runners and push-mirrors back to GitHub
- `llama.cpp` - local inference on the GPU
- Whisper Large v3 - speech-to-text
- Hermes - an always-on local agent
- Cognee - a knowledge graph with hybrid search over mail, calendar, finance, and repos
- Vaultwarden - password manager
- Delta - self-hosted todo platform
- the harivan.sh site

**`lib/theme.nix`**

- [cozybox.nvim](https://git.harivan.sh/harivansh-afk/cozybox.nvim) is the palette for everything: ghostty, fzf, lazygit, bat, zsh, omp, and the wallpaper
- `theme` flips dark/light everywhere, live

**`packages.nix`**

- one shared package set for both machines
- only truly macOS-specific things stay on Homebrew

**`scripts/`**

- runtime helpers (`hrd`, `ghpr`, `fork`, `iosrun`, and more), each exposed as a flake package

## Spark

A shared NixOS workstation on an NVIDIA DGX Spark (GB10, aarch64-linux).

- friends who want access get a user definition in `users/`; everyone gets the shared dotfile setup from `modules/users/`
- NVIDIA kernel, drivers, and container support come from the upstream [nixos-dgx-spark](https://github.com/graham33/nixos-dgx-spark) module
- disks declared with [disko](https://github.com/nix-community/disko); from-scratch provisioning via [nixos-anywhere](https://github.com/nix-community/nixos-anywhere)
- local inference runs Pi against `llama.cpp` on `127.0.0.1:8080`
- the Cognee graph rebuilds daily at 04:00 and renders to `/var/lib/kb/graph/index.html`; never network-served, `open kb-graph.html` streams it to the Mac

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
scripts/             runtime helpers (hrd, ghpr, fork, iosrun, theme, ...)
secrets/             sops-encrypted secrets per host
terraform/           declarative Cloudflare DNS via terranix
assets/              readme artwork
```
