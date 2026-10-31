{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) system;
in
{
  core =
    (with pkgs; [
      ast-grep
      fd
      gnupg
      jujutsu
      jq
      just
      mise
      nodejs_24
      pnpm
      pkg-config
      python3
      ripgrep
      rust-analyzer
      rustup
      tree
      uv
      wget
      zoxide
    ])
    ++ [
      inputs.devin-codex.packages.${system}.default
      inputs.cc-proxy.packages.${system}.default
    ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
      pkgs.file
      pkgs.gcc
      pkgs.xdg-utils
    ];

  extras = with pkgs; [
    cloudflared
    git-lfs
  ];

  darwinExtras = with pkgs; [
    coreutils-prefixed
    curl
    mosh
    rsync
  ];

  fonts = with pkgs; [
    (callPackage ./nonicons.nix { })
    nerd-fonts.symbols-only
  ];
}
