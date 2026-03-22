{
  inputs,
  lib,
  pkgs,
  username,
  ...
}: let
  packageSets = import ../lib/package-sets.nix {inherit inputs lib pkgs;};
in {
  nix.enable = true;

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [
      "@admin"
      username
    ];
  };

  nix.gc = {
    automatic = true;
    interval = {
      Weekday = 7;
      Hour = 3;
      Minute = 0;
    };
    options = "--delete-older-than 14d";
  };

  nixpkgs.config.allowUnfree = true;

  programs.zsh.enable = true;
  environment.shells = [pkgs.zsh];

  environment.systemPackages = packageSets.core;

  environment.variables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };
}
