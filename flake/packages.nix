# Wire packages/ into the flake. The registry (packages/registry.nix) is the
# single source of truth; this module turns it into per-system outputs:
#   - packages.<id>          -> nix build/run .#<id>   (filtered by `platforms`)
#   - checks.<id>-<test>     -> nix flake check        (from each package's tests)
#
# Adding a package is just dropping packages/<name>/package.nix; nothing here
# changes.
{ inputs, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      registry = import ../packages/registry.nix { inherit lib; };
      loaded = map (entry: import entry.path { inherit pkgs lib inputs system; }) registry;

      enabledForSystem = p: !(p ? platforms) || builtins.elem system p.platforms;
      enabled = builtins.filter enabledForSystem loaded;
    in
    {
      packages = builtins.listToAttrs (
        map (p: {
          name = p.id;
          value = p.package;
        }) enabled
      );

      checks = lib.foldl' (
        acc: p:
        acc
        // lib.mapAttrs' (testName: drv: lib.nameValuePair "${p.id}-${testName}" drv) (p.tests or { })
      ) { } enabled;
    };
}
