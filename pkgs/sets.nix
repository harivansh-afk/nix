{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) system;
  gwsPackage = inputs.googleworkspace-cli.packages.${system}.default or null;
in
{
  core =
    (with pkgs; [
      ast-grep
      bitwarden-cli
      elixir
      fd
      gnupg
      go_1_26
      jjui
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

  extras =
    (with pkgs; [
      awscli2
      bazel
      cloudflared
      git-filter-repo
      git-lfs
      go-tools
      golangci-lint
      google-cloud-sdk
      graphite-cli
      imagemagickBig
      kind
      kubectl
      kubernetes-helm
      lazygit
      libpq
      librsvg
      minikube
      ngrok
      phpPackages.composer
      postgresql_17
      terraform
      texliveFull
      typst
      watchman
    ])
    ++ (builtins.filter (p: p != null) [
      gwsPackage
    ]);

  darwinExtras = with pkgs; [
    coreutils-prefixed
    curl
    mosh
    pandoc
    rsync
    tailscale
    yt-dlp
  ];

  fonts = with pkgs; [
    (callPackage ./nonicons.nix { })
    nerd-fonts.symbols-only
  ];
}
