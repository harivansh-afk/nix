{
  inputs,
  lib,
  pkgs,
}:
let
  gwsPackage = inputs.googleworkspace-cli.packages.${pkgs.stdenv.hostPlatform.system}.default;
  claudePackage = inputs.claudeCode.packages.${pkgs.stdenv.hostPlatform.system}.default;
  agentcomputerPackage = inputs.agentcomputer-cli.packages.${pkgs.stdenv.hostPlatform.system}.default;
  openspecPackage = inputs.openspec.packages.${pkgs.stdenv.hostPlatform.system}.default;

  memex = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "memex";
    version = "0.3.1";

    src = pkgs.fetchurl {
      url = "https://github.com/nicosuave/memex/releases/download/v${version}/memex-${version}-macos-arm64.tar.gz";
      hash = "sha256-OIqT0xS+8vc0dQNi+YdDXLmN8V/7AT4Q/cnvbbhZ+3s=";
    };

    dontUnpack = true;

    installPhase = ''
      tar -xzf "$src"
      install -Dm755 memex "$out/bin/memex"
    '';

    meta = {
      description = "Fast local history search for Claude and Codex logs";
      homepage = "https://github.com/nicosuave/memex";
      license = lib.licenses.mit;
      mainProgram = "memex";
      platforms = lib.platforms.darwin;
    };
  };

  graphite = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "graphite";
    version = "1.7.20";

    src = pkgs.fetchurl {
      url = "https://github.com/withgraphite/homebrew-tap/releases/download/v${version}/gt-macos-arm64";
      hash = "sha256-ho9VQw1ic3jhG3yxNwUL0W1WvNFku9zw6DQnGehs7+8=";
    };

    dontUnpack = true;

    installPhase = ''
      install -Dm755 "$src" "$out/bin/gt"
    '';

    meta = {
      description = "Manage stacked Git changes and submit them for review";
      homepage = "https://graphite.dev/";
      license = lib.licenses.agpl3Only;
      mainProgram = "gt";
      platforms = lib.platforms.darwin;
    };
  };

  worktrunk = pkgs.rustPlatform.buildRustPackage rec {
    pname = "worktrunk";
    version = "0.23.1";

    src = pkgs.fetchurl {
      url = "https://github.com/max-sixty/worktrunk/archive/refs/tags/v${version}.tar.gz";
      hash = "sha256-cdQDUz7to3JkriWE9i5iJ2RftJFZivw7CTwGxDZPAqw=";
    };

    cargoHash = "sha256-DHjwNqMiVkWqL3CuOCITvyqkdKe+GOZ2nlMSstDIcTg=";
    doCheck = false;

    meta = {
      description = "CLI for Git worktree management";
      homepage = "https://worktrunk.dev";
      license = with lib.licenses; [
        asl20
        mit
      ];
      mainProgram = "wt";
      platforms = lib.platforms.darwin;
    };
  };
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
    python3
    ripgrep
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
      postgresql_17
      redis
      tailscale
      terraform
      texliveFull
      yt-dlp
    ])
    ++ lib.optionals pkgs.stdenv.isDarwin [
      agentcomputerPackage
    ]
    ++ [
      openspecPackage
    ]
    ++ lib.optionals pkgs.stdenv.isDarwin [
      graphite
      memex
      worktrunk
    ];

  fonts = with pkgs; [
    jetbrains-mono
    nerd-fonts.symbols-only
  ];
}
