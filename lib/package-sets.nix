{
  inputs,
  lib,
  pkgs,
}:
let
  gwsPackage = inputs.googleworkspace-cli.packages.${pkgs.stdenv.hostPlatform.system}.default;
  claudePackage = inputs.claudeCode.packages.${pkgs.stdenv.hostPlatform.system}.default;
  openspecPackage = inputs.openspec.packages.${pkgs.stdenv.hostPlatform.system}.default;

in
{
  core = with pkgs; [
    bitwarden-cli
    curl
    fd
    fzf
    gnupg
    go_1_26
    jq
    just
    nodejs_22
    pnpm
    python3
    ripgrep
    rsync
    rustup
    tree
    uv
    wget
    zoxide
  ];

  extras =
    (with pkgs; [
      awscli2
      claudePackage
      pkgs.codex
      coreutils-prefixed
      delta
      diff-so-fancy
      git-filter-repo
      git-lfs
      go-tools
      golangci-lint
      goose
      google-cloud-sdk
      gwsPackage
      imagemagickBig
      kind
      kubectl
      kubernetes-helm
      lazygit
      libpq
      librsvg
      llmfit
      minikube
      ngrok
      phpPackages.composer
      postgresql_17
      redis
      tailscale
      terraform
      yt-dlp
    ])
    ++ lib.optionals pkgs.stdenv.isLinux [
      pkgs.cadaver
    ]
    ++ lib.optionals pkgs.stdenv.isDarwin [
      pkgs.texliveFull
    ]
    ++ [
      openspecPackage
    ];

  fonts = with pkgs; [
    jetbrains-mono
    nerd-fonts.symbols-only
  ];
}
