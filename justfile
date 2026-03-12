default:
  just --list

check:
  nix flake check

build:
  nix build .#darwinConfigurations.hari-macbook-pro.system

switch:
  nix run github:LnL7/nix-darwin/master#darwin-rebuild -- switch --flake .#hari-macbook-pro

fmt:
  nix fmt

