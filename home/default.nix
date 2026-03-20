{...}: {
  imports = [
    ./bat.nix
    ./claude.nix
    ./codex.nix
    ./gcloud.nix
    ./gh.nix
    ./ghostty.nix
    ./git.nix
    ./karabiner.nix
    ./k9s.nix
    ./lazygit.nix
    ./migration.nix
    ./nvim.nix
    ./rectangle.nix
    ./scripts.nix
    ./tmux.nix
    ./zsh.nix
  ];

  home.stateVersion = "24.11";
  programs.home-manager.enable = true;
  xdg.enable = true;
}
