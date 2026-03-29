{
  inputs,
  lib,
  pkgs,
  username,
  ...
}: let
  packageSets = import ../../lib/package-sets.nix {inherit inputs lib pkgs;};
in {
  imports = [
    ../../home/netty.nix
  ];

  targets.genericLinux.enable = true;

  home = {
    inherit username;
    homeDirectory = "/home/${username}";
    packages = packageSets.core ++ packageSets.extras;
  };
}
