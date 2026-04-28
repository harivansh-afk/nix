{
  inputs,
  lib,
  pkgs,
  username,
  hostConfig,
  ...
}:
let
  packageSets = import ../packages.nix { inherit inputs lib pkgs; };
in
{
  nix.settings = {
    auto-optimise-store = true;
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [
      "root"
      username
    ];
    use-xdg-base-directories = true;
    max-jobs = "auto";
    cores = 0;
  };

  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays =
    lib.optionals (hostConfig.system != "aarch64-linux") [
      inputs.neovim-nightly.overlays.default
    ]
    ++ lib.optionals hostConfig.isDarwin [
      (_final: _prev: {
        nushell = inputs.nixpkgs-nushell.legacyPackages.${hostConfig.system}.nushell;
      })
    ];

  programs.zsh.enable = true;
  environment.shells = [ pkgs.zsh ];

  environment.systemPackages =
    packageSets.core
    ++ lib.optionals hostConfig.isLinux [
      pkgs.ghostty.terminfo
    ];

  environment.variables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };
}
