{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) system;
  gwsPackage = inputs.googleworkspace-cli.packages.${system}.default or null;
  # jj-ix: the patched jj that speaks the ix forge's store backend
  # (pkgs/jj-ix). Toolchain comes from rust-overlay via mkRustBin so the
  # main package set needs no overlay.
  jjIxPackage = pkgs.callPackage ./jj-ix {
    rust-bin = inputs.rust-overlay.lib.mkRustBin { } pkgs;
    inherit (inputs) ix-src;
  };
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
      nodejs_24
      nushell
      pnpm
      pkg-config
      python3
      ranger
      ripgrep
      rust-analyzer
      rustup
      tree
      uv
      wget
      zoxide
    ])
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
      eternal-terminal
      ngrok
      phpPackages.composer
      postgresql_17
      redis
      terraform
      texliveFull
      typst
      watchman
    ])
    ++ (builtins.filter (p: p != null) [
      gwsPackage
    ])
    ++ [ jjIxPackage ];

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
