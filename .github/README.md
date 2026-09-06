> [!IMPORTANT]
> This is a read-only mirror of <https://git.harivan.sh/harivansh-afk/nix>. Use Forgejo for issues, PRs, and active development.

# Nix

This repo is the home for all my configs and creations.

Everything is a single flake, declared with [flake-parts](https://github.com/hercules-ci/flake-parts) and managed by [Determinate Nix](https://docs.determinate.systems/determinate-nix/).

## Tour

**`dots/`**

- plain-file configs for ~28 tools: ghostty, zsh, git, lazygit, and more
- no home-manager: an activation script symlinks them into place
- my links point at the live checkout, so edits apply without a rebuild

**`dots/nvim/`**

- `pr` - code review inside Neovim: PR list, file tree, review marks, CI status, `pr://` buffers

**`hosts/spark/services/`**

- [Forgejo](https://git.harivan.sh) - my git
- llama.cpp - local model inference
- Whisper Large v3 - for speech-to-text using voice-ink
- Vaultwarden - password manager

**`lib/theme.nix`**

- [cozybox.nvim](https://git.harivan.sh/harivansh-afk/cozybox.nvim) is my custom palette for all my software

**`pkgs/sets.nix`**

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
flake/               host assembly, packages, devshell, args (incl. the host records)
lib/                 theme palette, remote registry, nvim plugin pinning
hosts/               per-host config; everything single-host lives here
  macbook/           darwin defaults, homebrew, launchd services, voiceink
  spark/             NixOS base + services/ (forgejo, inference, whisper, caddy, ...)
  ix/                the throwaway dev VM template
dots/                app configs symlinked into XDG paths (live-editable)
  nvim/              the Neovim setup: pr, statusline
  ...                one directory per tool
modules/             genuinely shared modules
  common.nix         nix settings, overlays, the shared package set
  security/          sops
  users/             shared dotfile and user setup, accounts/ user registry
pkgs/                derivations: package sets, jj-ix, packaged scripts
scripts/             repo tooling (CI smoke tests, lock regeneration)
secrets/             sops-encrypted secrets per host
terraform/           declarative Cloudflare DNS via terranix
assets/              readme artwork, wallpapers
```
