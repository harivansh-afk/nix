# LSPs and tools the dots/nvim config expects on PATH. Shared between the
# per-user package set (modules/users/user-config/packages.nix) and the
# portable `nix run .#nvim` wrapper (flake/portable.nix).
{ lib, pkgs }:
(with pkgs; [
  bat
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
])
# nix's clang wrapper puts cc/ld on PATH; on darwin that shadows Apple's
# toolchain and its ld can't see the macOS SDK (cargo/Tauri fail with
# "ld: library not found for -liconv"). clangd for nvim comes from
# clang-tools above; darwin uses Apple's /usr/bin/cc for compiling.
++ lib.optionals (!pkgs.stdenv.isDarwin) [ pkgs.clang ]
