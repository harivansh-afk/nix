{ lib, pkgs }:
(with pkgs; [
  bat
  clang-tools
  fd
  fzf
  gh
  git
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
])
++ [ (pkgs.callPackage ../pkgs/baml-cli { }) ]

++ lib.optionals (!pkgs.stdenv.isDarwin) [ pkgs.clang ]
