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
  # Determinate Nix owns the Nix installation, the daemon, and
  # /etc/nix/nix.conf. On NixOS the determinate module redirects
  # /etc/nix/nix.conf to /etc/nix/nix.custom.conf, so anything we set via
  # `nix.settings` here ends up in the custom config. On darwin the
  # determinate nix-darwin module force-disables `nix.*` and expects
  # equivalents via `determinateNix.customSettings` (set in flake/macbook.nix).
  # Garbage collection is handled by determinate-nixd, so don't set nix.gc.
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
  nixpkgs.overlays = [ inputs.neovim-nightly.overlays.default ];

  programs.zsh.enable = true;
  environment.shells = [ pkgs.zsh ];

  environment.systemPackages = packageSets.core;

  environment.variables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };
}
