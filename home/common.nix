{...}: {
  imports = [
    ./bat.nix
    ./eza.nix
    ./claude.nix
    ./codex.nix
    ./fzf.nix
    ./gcloud.nix
    ./gh.nix
    ./ghostty.nix
    ./git.nix
    ./k9s.nix
    ./lazygit.nix
    ./mise.nix
    ./migration.nix
    ./nvim.nix
    ./skills.nix
    ./scripts.nix
    ./ssh.nix
    ./tmux.nix
    ./zsh.nix
  ];

  home.stateVersion = "24.11";
  programs.home-manager.enable = true;
  xdg.enable = true;
}
