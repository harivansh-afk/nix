# Per-user package set: base CLI tools, the LSPs/tools nvim expects on PATH
# (the old programs.neovim extraPackages), the custom scripts, and any
# host-specific extras.
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
  nvimPackages = with pkgs; [
    bat
    clang
    clang-tools
    elixir_1_19
    elixir-ls
    fd
    fzf
    gh
    git
    go_1_26
    gopls
    lua-language-server
    pyright
    python3
    ripgrep
    stylua
    tree-sitter
    vscode-langservers-extracted
    bash-language-server
    typescript
    typescript-language-server
  ];
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
