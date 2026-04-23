# Nix Leveraging

Single dependency graph for my macOS laptop and DGX Spark workstation.

Using [determinate nix](https://docs.determinate.systems/determinate-nix/) for
the Nix install / daemon / base `nix.conf`, parallel builds, and better ux.

macbook — nix-darwin + home-manager + nix-homebrew

Home Manager is the userland control plane:
Rust, Go, Node, Python, AWS, and friends are routed into XDG paths;

SSH and GPG perms are locked on every activation.

A migration module handles the cutover from legacy symlinks.

[cozybox.nvim](https://github.com/harivansh-afk/cozybox.nvim) drives Ghostty, tmux, fzf, zsh syntax highlighting, bat, and delta, with a generated script to hot-swap light/dark.

configs are repo-owned (dots) rather than scattered across $HOME.

Global agent skills install declaratively.

Secrets live in self-hosted Bitwarden and render at activation time.

Deploy with `just switch` (macbook) or `just spark-switch` (spark).

The workstation (`spark`, NVIDIA DGX Spark, aarch64 NixOS) is managed by this
same flake. Hardware support — NVIDIA kernel, drivers, podman + CDI, fwupd,
Flox CUDA cache — comes from the upstream
[`graham33/nixos-dgx-spark`](https://github.com/graham33/nixos-dgx-spark)
module consumed as a flake input. Host-specific bits (users, tailscale,
services) live under `hosts/spark/`.

First-time install (target booted into any Linux with SSH):

```
just spark-install TARGET=root@<tailscale-ip>
```

This runs `nixos-anywhere` with `--generate-hardware-config` and
`--build-on-remote` so the closure (including the NVIDIA kernel) is built
on spark itself.

## Structure

```
flake.nix        inputs, outputs, per-host system assembly
justfile         switch, fmt, ci entry points
packages.nix     shared package set consumed by hosts
flake/           per-host assembly (args, devshell, hosts=darwin, nixos=spark)
lib/             host metadata + central theme palette
hosts/           host roots (macbook/, spark/)
system/          shared system-level nix config and packages
home/            home-manager modules, one file per tool
dots/            repo-owned app configs (symlinked into XDG)
scripts/         runtime scripts wired via home/scripts.nix
.forgejo/        CI workflows
```
