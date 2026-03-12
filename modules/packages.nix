{
  inputs,
  pkgs,
  username,
  ...
}: let
  berkeleyMono = pkgs.stdenvNoCC.mkDerivation {
    pname = "berkeley-mono";
    version = "local";
    src = /. + "/Users/${username}/Library/Fonts/BerkeleyMono-Regular.otf";
    dontUnpack = true;
    installPhase = ''
      install -Dm644 "$src" "$out/share/fonts/opentype/BerkeleyMono-Regular.otf"
    '';
  };

  gwsPackage =
    inputs.googleworkspace-cli.packages.${pkgs.stdenv.hostPlatform.system}.default;
in {
  environment.systemPackages = with pkgs; [
    codex
    coreutils-prefixed
    delta
    diff-so-fancy
    git-filter-repo
    git-lfs
    google-cloud-sdk
    gwsPackage
    imagemagickBig
    lazygit
    libpq
    librsvg
    llmfit
    mise
    ngrok
    postgresql_16
    redis
    tailscale
    terraform
    yt-dlp
  ];

  fonts.packages = with pkgs; [
    berkeleyMono
    jetbrains-mono
    nerd-fonts.symbols-only
  ];
}
