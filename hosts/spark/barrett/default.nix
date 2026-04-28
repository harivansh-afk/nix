{ pkgs, ... }:
{
  home.stateVersion = "24.11";
  programs.home-manager.enable = true;
  xdg.enable = true;

  home.packages = with pkgs; [
    # add your packages here
  ];
}
