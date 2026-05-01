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
        sudo --set-home --preserve-env=PATH \
          nix run .#darwin-rebuild -- switch --flake .#macbook
        ;;
      Linux)
        nix run nixpkgs#nixos-rebuild -- switch \
          --flake .#spark \
          --sudo \
          --no-reexec
        ;;
      *)
        echo "Unsupported OS: $(uname -s)" >&2
        exit 1
        ;;
    esac

switch-spark:
    nix run nixpkgs#nixos-rebuild -- switch \
      --flake .#spark \
      --target-host rathi@spark \
      --build-host rathi@spark \
      --sudo \
      --no-reexec

# --- tailscale ACL ---

acl-push:
    @test -n "$TS_API_KEY" || { echo "Set TS_API_KEY (from https://login.tailscale.com/admin/settings/keys)"; exit 1; }
    curl -sS -X POST "https://api.tailscale.com/api/v2/tailnet/-/acl" \
      -u "$TS_API_KEY:" \
      -H "Content-Type: application/hujson" \
      --data-binary @tailscale/policy.hujson
    @echo "\nACL policy pushed."

# --- secrets ---

sops-edit FILE:
    SOPS_AGE_KEY_FILE=${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt} \
      nix run nixpkgs#sops -- {{FILE}}
