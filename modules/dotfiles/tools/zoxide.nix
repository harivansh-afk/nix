{ pkgs, lib, ... }:
{
  packages = [ pkgs.zoxide ];

  zshInit = lib.mkOrder 850 ''
    eval "$(${pkgs.zoxide}/bin/zoxide init zsh)"
  '';
}
