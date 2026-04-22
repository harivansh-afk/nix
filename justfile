set shell := ["bash", "-euo", "pipefail", "-c"]

export NIX_CONFIG := "experimental-features = nix-command flakes"

default:
    @just --list

check:
    nix flake check

fmt:
    nix fmt

switch:
    sudo --set-home --preserve-env=PATH \
      nix run .#darwin-rebuild -- switch --flake .#macbook

# Build + switch the spark NixOS host remotely. Run from the macbook;
# the aarch64-linux closure is built on spark itself to avoid cross-compile.
spark-switch:
    nixos-rebuild switch \
      --flake .#spark \
      --target-host rathi@spark \
      --build-host rathi@spark \
      --use-remote-sudo

spark-build:
    nix build .#nixosConfigurations.spark.config.system.build.toplevel \
      --builders 'ssh://rathi@spark aarch64-linux' || \
    nix build .#nixosConfigurations.spark.config.system.build.toplevel

# First-time install via nixos-anywhere. Target must already be booted
# into a Linux with SSH + a sudoer / root. Generates hardware-configuration.nix
# on-device the first time through. Pass TARGET=user@host or TARGET=root@ip.
spark-install target='root@spark':
    nix run github:nix-community/nixos-anywhere -- \
      --flake .#spark \
      --generate-hardware-config nixos-generate-config hosts/spark/hardware-configuration.nix \
      --build-on-remote \
      {{target}}

spark-vm-test:
    nix run github:nix-community/nixos-anywhere -- --flake .#spark --vm-test

secrets-sync:
    ./scripts/lib/render-bw-shell-secrets.sh
    ./scripts/lib/restore-bw-files.sh

sync-agent-history:
    ./scripts/lib/sync-agent-history.sh

search-agent-history query='':
    ./scripts/lib/search-agent-history.sh "{{query}}"
