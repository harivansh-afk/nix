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
  environment.systemPackages =
    packageSets.extras ++ lib.optionals hostConfig.isDarwin packageSets.darwinExtras;

  fonts.packages = packageSets.fonts;
}
