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
  # Two local fixes on top of the upstream herdr build (pkgs/herdr/*.patch):
  #   - rounded outer pane corners; herdr hardcodes the square glyphs in
  #     src/ui/panes.rs and exposes no border-style config key.
  #   - visible selection/copy-mode highlight when the outer terminal never
  #     answers herdr's OSC 10/11 color query. mosh (how `hrd` attaches) drops
  #     that response, and the fallback painted the selection in panel_bg -
  #     i.e. the pane's own background, so the highlight was invisible.
  # Patching forces a source build of herdr (rust + vendored zig libghostty-vt)
  # instead of substituting the upstream artifact. Drop these once upstream
  # ships a border-style option and fixes the selection fallback.
  herdrBase = inputs.herdr.packages.${system}.default or null;
  herdrPackage =
    if herdrBase == null then
      null
    else
      herdrBase.overrideAttrs (prev: {
        patches = (prev.patches or [ ]) ++ [ ./pkgs/herdr/rounded-borders-and-mosh-selection.patch ];
      });
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
      rsync
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
      herdrPackage
    ]);

  darwinExtras = with pkgs; [
    coreutils-prefixed
    pandoc
    yt-dlp
  ];

  fonts = with pkgs; [
    nerd-fonts.symbols-only
  ];
}
