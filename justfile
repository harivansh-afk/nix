set shell := ["bash", "-euo", "pipefail", "-c"]

export NIX_CONFIG := "experimental-features = nix-command flakes"

default:
    @just --list

check:
    nix flake check

fmt:
    nix fmt

switch:
    #!/usr/bin/env bash
    set -euo pipefail
    case "$(uname -s)" in
      Darwin)
        nix run nixpkgs#nh -- darwin switch . -H macbook
        ;;
      Linux)
        nix run nixpkgs#nh -- os switch . -H spark
        ;;
      *)
        echo "Unsupported OS: $(uname -s)" >&2
        exit 1
        ;;
    esac

switch-spark:
    nix run nixpkgs#nh -- os switch . -H spark \
      --target-host rathi@spark \
      --build-host rathi@spark

# --- dns (cloudflare) ---

dns-init:
    nix run .#cloudflare-dns -- init

dns-plan:
    nix run .#cloudflare-dns -- plan

dns-apply:
    nix run .#cloudflare-dns -- apply

# --- secrets ---

sops-edit FILE:
    SOPS_AGE_KEY_FILE=${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt} \
      nix run nixpkgs#sops -- {{FILE}}
