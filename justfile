set shell := ["bash", "-euo", "pipefail", "-c"]

export NIX_CONFIG := "experimental-features = nix-command flakes"

default:
    @just --list

check:
    nix flake check

fmt:
    nix fmt

# --- macbook ---

switch:
    sudo --set-home --preserve-env=PATH \
      nix run .#darwin-rebuild -- switch --flake .#macbook

# --- spark ---

# Remote rebuild + switch on spark. Assumes `rathi` has NOPASSWD sudo
# there (see hosts/spark/users.nix); drop `--sudo` and add
# `--ask-sudo-password` if that assumption ever changes.
spark-switch:
    nix run nixpkgs#nixos-rebuild -- switch \
      --flake .#spark \
      --target-host rathi@spark \
      --build-host rathi@spark \
      --sudo

# First-ever install on spark (or full reinstall). Upstream template
# from graham33/nixos-dgx-spark; expect ~30-40 min for the NVIDIA
# kernel on a cold build. TARGET must be `user@host` on a fresh box.
spark-install TARGET:
    nix run github:nix-community/nixos-anywhere -- \
      --flake .#spark \
      --generate-hardware-config nixos-generate-config hosts/spark/hardware-configuration.nix \
      --build-on-remote \
      {{TARGET}}

# --- secrets ---

# Edit a sops-encrypted secret in-place. Usage: `just sops-edit secrets/spark/foo.env`
sops-edit FILE:
    SOPS_AGE_KEY_FILE=${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt} \
      nix run nixpkgs#sops -- {{FILE}}
