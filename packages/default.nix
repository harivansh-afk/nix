# The "packageSet" view of packages/: a plain attrset { <id> = <derivation>; }
# for NixOS / nix-darwin modules to consume directly, e.g.
#   customPackages = import ../../packages { inherit pkgs lib; };
#   environment.systemPackages = [ customPackages.bash-macros ];
#
# This is the same registry flake/packages.nix uses, so the two views can never
# drift. `inputs` defaults to {} because most packages do not need flake inputs;
# only `.package` of an input-using package forces them, never `.id`.
{
  pkgs,
  lib,
  inputs ? { },
  system ? pkgs.stdenv.hostPlatform.system,
}:
let
  registry = import ./registry.nix { inherit lib; };
  load = entry: import entry.path { inherit pkgs lib inputs system; };
in
builtins.listToAttrs (
  map (
    entry:
    let
      p = load entry;
    in
    {
      name = p.id;
      value = p.package;
    }
  ) registry
)
