# nix

**macbook** - MacBook (aarch64-darwin) running nix-darwin + nix-homebrew

**spark** - NVIDIA DGX Spark (aarch64-linux) running NixOS

Both are declared in one flake using [flake-parts](https://github.com/hercules-ci/flake-parts) and managed with [Determinate Nix](https://docs.determinate.systems/determinate-nix/)
configs live in `dots/` and get symlinked into XDG paths via `modules/dotfiles`

Spark is a shared NixOS workstation

Friends who want access get a user definition in `users` and per-user dotfiles config under `hosts/spark/<name>`

NVIDIA kernel, drivers, and container support come from the upstream [nixos-dgx-spark](https://github.com/graham33/nixos-dgx-spark) module

Secrets are managed with [sops-nix](https://github.com/Mic92/sops-nix)

[cozybox.nvim](https://git.harivan.sh/harivansh-afk/cozybox.nvim) provides the unified theme across everything

## Spark access

Spark SSH is private tailnet-only. `spark` resolves on the personal tailnet and is the normal SSH entry point; the old Cloudflare Access SSH path is gone.

Spark runs two Tailscale identities:

- `spark-ix` on the Indexable tailnet for shared service routing and Funnel/Serve.
- `spark` on the personal tailnet for admin SSH and personal access.

```sh
mosh spark
ssh spark
```

Use `ssh spark-lan` only for direct LAN access at home.

Spark local inference runs Pi against `llama.cpp` on `127.0.0.1:8080`

## Structure

```
flake.nix          entrypoint - inputs and outputs
flake/             host assembly, devshell, args
lib/               host metadata, theme palette, paths helper
hosts/             per-host config (macbook/, spark/)
users/             multi-user definitions for spark
modules/dotfiles/  per-user dotfile materialization (replaces home-manager)
  options.nix      submodule type for dotfiles.users.<name>
  tools/           one file per tool (zsh, git, tmux, neovim, ...)
  platform/        linux + darwin activation finalizers
dots/              app configs symlinked into XDG
modules/           reusable NixOS modules (services, security)
system/            shared system-level config and packages
scripts/           runtime scripts wired via tools/scripts.nix
secrets/           sops-encrypted secrets per host
```
