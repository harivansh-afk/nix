# nix

**macbook** - MacBook (aarch64-darwin) running nix-darwin + nix-homebrew

**spark** - NVIDIA DGX Spark (aarch64-linux) running NixOS

Both are declared in one flake using [flake-parts](https://github.com/hercules-ci/flake-parts) and managed with [Determinate Nix](https://docs.determinate.systems/determinate-nix/)
configs live in `dots/` and get symlinked into XDG paths

NVIDIA kernel, drivers, and container support come from the upstream [nixos-dgx-spark](https://github.com/graham33/nixos-dgx-spark) module

Secrets are managed with [sops-nix](https://github.com/Mic92/sops-nix) and [vaultwarden](https://github.com/dani-garcia/vaultwarden)

[cozybox.nvim](https://git.harivan.sh/harivansh-afk/cozybox.nvim) provides the unified theme for everything

### Spark

Spark is a shared NixOS workstation

Friends who want access get a user definition in `users`; every user gets the shared dotfile setup from `modules/users/` (their symlinks point at the nix-store copy of `dots/`, the owner's at the live checkout)

`spark` resolves on the personal tailnet and is the normal SSH/mosh entry point. It runs two Tailscale identities:

- `spark-ix` on the Indexable tailnet for shared service routing and Funnel/Serve
- `spark` on the personal tailnet for admin SSH and personal access

Use `ssh spark-lan` only for direct LAN access on shared network

Spark local inference runs Pi against `llama.cpp` on `127.0.0.1:8080`

## Structure

```
flake.nix          entrypoint - inputs and outputs
flake/             host assembly, devshell, args
lib/               host metadata, theme palette
inventory/         typed host inventory via evalModules
hosts/             per-host config (macbook/, spark/)
users/             multi-user definitions for spark
dots/              app configs symlinked into XDG paths (live-editable)
modules/           reusable modules (services, security, users/dotfiles)
system/            shared system-level config and packages
scripts/           runtime scripts wired via modules/users/user-config.nix
secrets/           sops-encrypted secrets per host
terraform/         declarative Cloudflare DNS via terranix
```
