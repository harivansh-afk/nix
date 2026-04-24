{
  inputs,
  lib,
  pkgs,
  hostConfig,
  ...
}:
let
  packageSets = import ../packages.nix { inherit inputs lib pkgs; };
in
{
  # Keep the shared dev toolchain aligned across both hosts. Only the
  # Darwin-specific compatibility packages stay behind the platform gate.
  environment.systemPackages =
    packageSets.extras
    ++ lib.optionals hostConfig.isDarwin packageSets.darwinExtras;

  fonts.packages = packageSets.fonts;
}
