default:
  just --list

check:
  nix --extra-experimental-features 'nix-command flakes' flake check

build config='darwin':
  #!/usr/bin/env bash
  if [[ "{{config}}" == "darwin" ]]; then
    nix --extra-experimental-features 'nix-command flakes' build path:.#darwinConfigurations.{{config}}.system
  else
    nix --extra-experimental-features 'nix-command flakes' run github:nix-community/home-manager -- build --flake path:.#{{config}}
  fi

switch config='darwin':
  #!/usr/bin/env bash
  if [[ "{{config}}" == "darwin" ]]; then
    sudo env PATH="$PATH" nix --extra-experimental-features 'nix-command flakes' run github:nix-darwin/nix-darwin/master#darwin-rebuild -- switch --flake path:.#{{config}}
  else
    backup_ext="hm-bak-$(date +%Y%m%d-%H%M%S)"
    nix --extra-experimental-features 'nix-command flakes' run github:nix-community/home-manager -- switch --flake path:.#{{config}} -b "$backup_ext"
  fi

fmt:
  nix --extra-experimental-features 'nix-command flakes' fmt

secrets-sync:
  ./scripts/render-bw-shell-secrets.sh
  ./scripts/restore-bw-files.sh

sync-browser-auth:
  ./scripts/sync-bw-browser-auth.sh

sync-agent-history:
  ./scripts/sync-agent-history.sh

search-agent-history query='':
  ./scripts/search-agent-history.sh "{{query}}"

switch-netty:
  ssh root@netty "nixos-rebuild switch --flake github:harivansh-afk/nix#netty --refresh"
