## Nix

```
flake.nix            entrypoint - inputs and outputs
flake/               host assembly, packages, devshell, args (incl. the host records)
lib/                 theme palette, remote registry, nvim plugin pinning
hosts/               per-host config; everything single-host lives here
  macbook/           darwin defaults, homebrew, launchd services, voiceink
  spark/             NixOS base + services/ (forgejo, inference, caddy, ...)
dots/                app configs symlinked into XDG paths (live-editable)
  nvim/              the Neovim setup: pr, statusline
  ...                one directory per tool
modules/             genuinely shared modules
  common.nix         nix settings, overlays, the shared package set
  security/          sops
  users/             shared dotfile and user setup, accounts/ user registry
pkgs/                derivations: package sets, packaged scripts
scripts/             repo tooling (CI smoke tests, lock regeneration)
secrets/             sops-encrypted secrets per host
terraform/           declarative Cloudflare DNS via terranix
assets/              readme artwork, wallpapers
```
