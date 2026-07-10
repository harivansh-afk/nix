> [!IMPORTANT]
> This is a read-only mirror of <https://git.harivan.sh/harivansh-afk/nix>. Use Forgejo for issues, PRs, and active development.

<p align="center">
  <img src="https://raw.githubusercontent.com/harivansh-afk/nix/main/assets/hero.svg" alt="system map: one flake driving a nix-darwin macbook and a NixOS DGX Spark, with edge routing, services, theme, mux, and secrets" width="100%">
</p>

One flake, two machines, declared with [flake-parts](https://github.com/hercules-ci/flake-parts) and managed by [Determinate Nix](https://docs.determinate.systems/determinate-nix/):

| host | hardware | system | role |
|---|---|---|---|
| `macbook` | MacBook (aarch64-darwin) | nix-darwin + nix-homebrew | dev workstation |
| `spark` | NVIDIA DGX Spark, GB10 (aarch64-linux) | NixOS | shared server |

Configs live in `dots/` and get symlinked into XDG paths, no home-manager. NVIDIA kernel, drivers, and container support come from the upstream [nixos-dgx-spark](https://github.com/graham33/nixos-dgx-spark) module. Secrets are managed with [sops-nix](https://github.com/Mic92/sops-nix). [cozybox.nvim](https://github.com/harivansh-afk/cozybox.nvim) provides the unified theme for everything.

The full tour lives in the [Forgejo README](https://git.harivan.sh/harivansh-afk/nix).

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
assets/            readme artwork
```
