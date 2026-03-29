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
    nix --extra-experimental-features 'nix-command flakes' run github:nix-community/home-manager -- switch --flake path:.#{{config}} -b hm-bak
  fi

fmt:
  nix --extra-experimental-features 'nix-command flakes' fmt

secrets-sync:
  ./scripts/render-bw-shell-secrets.sh

secrets-restore-files:
  ./scripts/restore-bw-files.sh

switch-netty:
  nixos-rebuild switch --flake path:.#linux --target-host rathi@152.53.195.59 --build-on-remote --use-remote-sudo
