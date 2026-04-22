{
  inputs,
  lib,
  pkgs,
  username,
  ...
}:
let
  packageSets = import ../packages.nix { inherit inputs lib pkgs; };
in
{
  nix.enable = true;

  nix.settings = {
    auto-optimise-store = true;
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [
      "@admin"
      username
    ];
    use-xdg-base-directories = true;
    max-jobs = "auto";
    cores = 0;
  };

  nix.gc = {
    automatic = true;
    options = lib.mkDefault "--delete-older-than 14d";
  }
  // (
    if pkgs.stdenv.isDarwin then
      {
        interval = {
          Weekday = 7;
          Hour = 3;
          Minute = 0;
        };
      }
    else
      {
        dates = "weekly";
      }
  );

  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [ inputs.neovim-nightly.overlays.default ];

  programs.zsh.enable = true;
  environment.shells = [ pkgs.zsh ];

  environment.systemPackages = packageSets.core;

  environment.variables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };
}
