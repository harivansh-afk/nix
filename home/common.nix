{ config, ... }:
{
  _module.args.theme = import ../lib/theme.nix { inherit config; };

  imports = [
    ./agent-browser.nix
    ./bat.nix
    ./eza.nix
    ./claude.nix
    ./cursor.nix
    ./devin.nix
    ./xdg.nix
    ./security.nix
    ./codex.nix
    ./fzf.nix
    ./gcloud.nix
    ./gh.nix
    ./ghostty.nix
    ./git.nix
    ./k9s.nix
    ./lazygit.nix
    ./migration.nix
    ./nvim.nix
    ./hermes.nix
    ./prompt.nix
    ./skills.nix
    ./scripts.nix
    ./ssh.nix
    ./tea.nix
    ./tmux.nix
    ./zsh.nix
  ];

  home.stateVersion = "24.11";
  programs.home-manager.enable = true;
  xdg.enable = true;

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };
}
