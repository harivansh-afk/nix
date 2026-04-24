{
  inputs,
  pkgs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  # These flakes don't publish every system. Looking them up eagerly at
  # the top level would make the whole package set fail to evaluate on
  # e.g. aarch64-linux even if the consumer never touches `extras`.
  gwsPackage = inputs.googleworkspace-cli.packages.${system}.default or null;
  claudePackage = inputs.claudeCode.packages.${system}.default or null;
  openspecPackage = inputs.openspec.packages.${system}.default or null;

in
{
  core = with pkgs; [
    bitwarden-cli
    btop
    curl
    fd
    fzf
    gnupg
    gcc
    go_1_26
    jujutsu
    jq
    just
    nodejs_24
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
      buck2
      delta
      diff-so-fancy
      git-filter-repo
      git-lfs
      go-tools
      golangci-lint
      goose
      google-cloud-sdk
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
    ])
    ++ (builtins.filter (p: p != null) [
      claudePackage
      gwsPackage
      openspecPackage
    ]);

  darwinExtras = with pkgs; [
    coreutils-prefixed
    yt-dlp
  ];

  # Berkeley Mono (the primary user-facing monospace font) is installed
  # manually out-of-band; this flake only provides the nerd-fonts symbol
  # glyphs used as icon/powerline fallback.
  fonts = with pkgs; [
    nerd-fonts.symbols-only
  ];
}
