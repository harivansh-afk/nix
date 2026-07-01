{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) system;
  gwsPackage = inputs.googleworkspace-cli.packages.${system}.default or null;
  openspecPackage = inputs.openspec.packages.${system}.default or null;
in
{
  core =
    (with pkgs; [
      ast-grep
      bitwarden-cli
      curl
      elixir
      fd
      gnupg
      go_1_26
      jujutsu
      jq
      just
      nodejs_24
      nushell
      pnpm
      pkg-config
      python3
      ranger
      ripgrep
      rsync
      rust-analyzer
      rustup
      tree
      uv
      wget
      zoxide
    ])
    ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
      pkgs.gcc
    ];

  extras =
    (with pkgs; [
      awscli2
      bazel
      cloudflared
      delta
      diff-so-fancy
      git-filter-repo
      git-lfs
      go-tools
      golangci-lint
      goose
      google-cloud-sdk
      graphite-cli
      imagemagickBig
      kind
      kubectl
      kubernetes-helm
      lazygit
      libpq
      librsvg
      llmfit
      minikube
      mgrep
      mosh
      eternal-terminal
      ngrok
      phpPackages.composer
      postgresql_17
      redis
      tailscale
      terraform
      texliveFull
      typst
      watchman
    ])
    ++ (builtins.filter (p: p != null) [
      gwsPackage
      openspecPackage
    ]);

  darwinExtras = with pkgs; [
    coreutils-prefixed
    yt-dlp
  ];

  fonts = with pkgs; [
    nerd-fonts.symbols-only
  ];
}
