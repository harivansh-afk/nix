{
  inputs,
  pkgs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  gwsPackage = inputs.googleworkspace-cli.packages.${system}.default or null;
  claudePackage = inputs.claudeCode.packages.${system}.default or null;
  openspecPackage = inputs.openspec.packages.${system}.default or null;
  pinnedBuck2 = pkgs.callPackage ./system/buck2.nix { };

in
{
  core = with pkgs; [
    bitwarden-cli
    btop
    curl
    fd
    gnupg
    gcc
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
  ];

  extras =
    (with pkgs; [
      awscli2
      bazel
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
      claudePackage
      gwsPackage
      openspecPackage
      pinnedBuck2
    ]);

  darwinExtras = with pkgs; [
    coreutils-prefixed
    yt-dlp
  ];

  fonts = with pkgs; [
    nerd-fonts.symbols-only
  ];
}
