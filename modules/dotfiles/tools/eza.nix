{ pkgs, lib, ... }:
let
  ezaArgs = "--icons=auto --git --group-directories-first --header";
in
{
  packages = [ pkgs.eza ];

  zshInit = lib.mkOrder 850 ''
    alias ls='${pkgs.eza}/bin/eza ${ezaArgs}'
    alias ll='${pkgs.eza}/bin/eza ${ezaArgs} -l'
    alias la='${pkgs.eza}/bin/eza ${ezaArgs} -a'
    alias lla='${pkgs.eza}/bin/eza ${ezaArgs} -la'
    alias lt='${pkgs.eza}/bin/eza ${ezaArgs} --tree'
  '';
}
