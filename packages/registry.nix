# Package registry: auto-discovery for packages/.
#
# Every packages/<name>/ directory that contains a package.nix is a package.
# Drop a directory in, and it is picked up everywhere with zero extra wiring:
#   - flake/packages.nix exposes it as `nix build/run .#<id>` (host-scoped)
#     and turns each of its `tests` into a `nix flake check` entry.
#   - packages/default.nix exposes it as a plain pkgs-style attrset for NixOS /
#     nix-darwin modules to consume (`(import ../../packages { ... }).<id>`).
#
# A package.nix is a function:
#   { pkgs, lib, inputs, system, ... }: {
#     id        = "kb-search";                 # flake output / attrset key (required)
#     platforms = [ "aarch64-linux" ];         # optional; omitted = all systems
#     package   = <derivation>;                # the build (required)
#     tests     = { smoke = <derivation>; };   # optional; each -> a flake check
#   }
#
# Reading `.id` must never force `.package`, so a package can declare itself
# without its build inputs being available (see how cloudflare-dns keeps its
# terranix wiring inside a `let` that only `.package` forces).
{ lib }:
let
  entries = builtins.readDir ./.;
  isPackageDir = name: type: type == "directory" && builtins.pathExists (./. + "/${name}/package.nix");
  names = builtins.attrNames (lib.filterAttrs isPackageDir entries);
in
map (name: {
  inherit name;
  path = ./. + "/${name}/package.nix";
}) names
