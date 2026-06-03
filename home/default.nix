{ config, ... }:
{
  _module.args.theme = import ../lib/theme.nix { inherit config; };

  imports = [
    ./common.nix
    ./bat.nix
    ./btop.nix
    ./claude.nix
    ./codex.nix
    ./cursor-agent.nix
    ./devin.nix
    ./direnv.nix
    ./eza.nix
    ./fzf.nix
    ./gcloud.nix
    ./gh.nix
    ./git.nix
    ./k9s.nix
    ./lazygit.nix
    ./nvim.nix
    ./openwhispr.nix
    ./prompt.nix
    ./scripts.nix
    ./security.nix
    ./skills.nix
    ./ssh.nix
    ./tea.nix
    ./tmux.nix
    ./xdg.nix
    ./zoxide.nix
    ./zsh.nix
  ];

  home.stateVersion = "24.11";
  programs.home-manager.enable = true;
  xdg.enable = true;
}
