{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  packageSets = import ../lib/package-sets.nix { inherit inputs lib pkgs; };
in
{
  environment.systemPackages = packageSets.extras;
  fonts.packages = packageSets.fonts;
}
