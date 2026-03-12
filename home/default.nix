{...}: {
  imports = [
    ./bat.nix
    ./dotfiles.nix
    ./ghostty.nix
    ./git.nix
    ./tmux.nix
  ];

  home.stateVersion = "24.11";
  programs.home-manager.enable = true;
}
