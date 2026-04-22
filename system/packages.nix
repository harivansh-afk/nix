{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  packageSets = import ../packages.nix { inherit inputs lib pkgs; };
in
{
  environment.systemPackages = packageSets.extras;
  fonts.packages = packageSets.fonts;
}
