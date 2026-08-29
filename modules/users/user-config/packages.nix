# Per-user package set: base CLI tools, the LSPs/tools nvim expects on PATH
# (the old programs.neovim extraPackages, shared with the portable
# `nix run .#nvim` wrapper via lib/nvim-packages.nix), the custom scripts,
# and any host-specific extras.
{
  lib,
  pkgs,
  isDarwin,
  customScripts,
  nvimAliases,
  extraPackages,
  ...
}:
let
  nvimPackages = import ../../../lib/nvim-packages.nix { inherit lib pkgs; };
in
(with pkgs; [
  bat
  btop
  direnv
  eza
  fzf
  git
  git-lfs
  gh
  k9s
  neovim
  nvimAliases
  tea
])
++ nvimPackages
++ extraPackages
++ builtins.attrValues customScripts.commonPackages
++ lib.optionals isDarwin (builtins.attrValues customScripts.darwinPackages ++ [ pkgs.aerospace ])
