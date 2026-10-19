{
  inputs,
  lib,
  pkgs,
  username,
  hostConfig,
  ...
}:
let
  packageSets = import ../pkgs/sets.nix { inherit inputs lib pkgs; };
in
{

  nix.settings = import ./nix-settings.nix username;

  nixpkgs.config.allowUnfree = true;

  programs.zsh.enable = true;
  environment.shells = lib.optionals hostConfig.isDarwin [ pkgs.zsh ];

  environment.systemPackages =
    packageSets.core
    ++ packageSets.extras
    ++ lib.optionals hostConfig.isLinux [
      pkgs.ghostty.terminfo
    ]
    ++ lib.optionals hostConfig.isDarwin (
      packageSets.darwinExtras
      ++ [
        pkgs.ghostty-bin.terminfo
        pkgs.nh
      ]
    );

  fonts.packages = packageSets.fonts;

  environment.variables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };
}
