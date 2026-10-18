{
  lib,
  pkgs,
  isDarwin,
  customScripts,
  nvimAliases,
  neovim,
  extraPackages,
  ...
}:
let
  nvimPackages = import ../../../lib/nvim-packages.nix { inherit lib pkgs; };
in
(with pkgs; [
  btop
  direnv
  eza
  nvimAliases
  pi-coding-agent
  tea
])
++ [ neovim ]
++ nvimPackages
++ extraPackages
++ builtins.attrValues customScripts.commonPackages
++ lib.optionals isDarwin (builtins.attrValues customScripts.darwinPackages ++ [ pkgs.aerospace ])
