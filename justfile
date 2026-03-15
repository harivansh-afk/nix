default:
  just --list

check:
  nix --extra-experimental-features 'nix-command flakes' flake check

build:
  nix --extra-experimental-features 'nix-command flakes' build .#darwinConfigurations.hari-macbook-pro.system

switch:
  sudo env PATH="$PATH" nix --extra-experimental-features 'nix-command flakes' run github:LnL7/nix-darwin/master#darwin-rebuild -- switch --flake .#hari-macbook-pro

fmt:
  nix --extra-experimental-features 'nix-command flakes' fmt

secrets-sync:
  ./scripts/render-bw-shell-secrets.sh

secrets-restore-files:
  ./scripts/restore-bw-files.sh
