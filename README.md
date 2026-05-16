# nix

**macbook** - MacBook (aarch64-darwin) running nix-darwin + home-manager + nix-homebrew

**spark** - NVIDIA DGX Spark (aarch64-linux) running NixOS

Both are declared in one flake using [flake-parts](https://github.com/hercules-ci/flake-parts) and managed with [Determinate Nix](https://docs.determinate.systems/determinate-nix/)
configs live in `dots/` and get symlinked into XDG paths

Spark is a shared NixOS workstation

Friends who want access get a user definition in `users` and per-user home-manager config under `hosts/spark/<name>`

NVIDIA kernel, drivers, and container support come from the upstream [nixos-dgx-spark](https://github.com/graham33/nixos-dgx-spark) module

Secrets are managed with [sops-nix](https://github.com/Mic92/sops-nix)

[cozybox.nvim](https://git.harivan.sh/harivansh-afk/cozybox.nvim) provides the unified theme across everything

## Cloudflare SSH and mosh

Spark exposes SSH through the existing Cloudflare tunnel at `spark.harivan.sh`. The tunnel forwards `spark.harivan.sh` to `sshd` on `127.0.0.1:22`; Caddy is not in this path. I use mosh for extended SSH access over direct IP / tailnet when coding on remote machines.

```sh
mosh spark
ssh spark.harivan.sh
```

Unmanaged clients need `cloudflared` and an SSH config `ProxyCommand` for `spark.harivan.sh`; raw OpenSSH alone is not expected to pass through Cloudflare Access.

Spark local inference runs Pi against `llama.cpp` on `127.0.0.1:8080`

## Structure

```
flake.nix          entrypoint - inputs and outputs
flake/             host assembly, devshell, args
lib/               host metadata, theme palette
hosts/             per-host config (macbook/, spark/)
users/             multi-user definitions for spark
home/              home-manager modules, one file per tool
dots/              app configs symlinked into XDG
modules/           reusable NixOS modules (services, security)
system/            shared system-level config and packages
scripts/           runtime scripts wired via home/scripts.nix
secrets/           sops-encrypted secrets per host
```
