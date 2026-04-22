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

switch-netty:
    ssh root@netty "nixos-rebuild switch --flake github:harivansh-afk/nix#netty --refresh"

secrets-sync:
    ./scripts/lib/render-bw-shell-secrets.sh
    ./scripts/lib/restore-bw-files.sh

sync-agent-history:
    ./scripts/lib/sync-agent-history.sh

search-agent-history query='':
    ./scripts/lib/search-agent-history.sh "{{query}}"
