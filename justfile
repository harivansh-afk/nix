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

switch-spark:
    nix run nixpkgs#nixos-rebuild -- switch \
      --flake .#spark \
      --target-host rathi@spark \
      --build-host rathi@spark \
      --sudo

# --- secrets ---

sops-edit FILE:
    SOPS_AGE_KEY_FILE=${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt} \
      nix run nixpkgs#sops -- {{FILE}}
