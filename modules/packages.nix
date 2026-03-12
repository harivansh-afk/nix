{
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
in {
  environment.systemPackages = with pkgs; [
    arrow-cpp
    binwalk
    cloc
    cloudflared
    cmakeCurses
    codex
    coreutils-prefixed
    criterion
    delta
    diff-so-fancy
    e2fsprogs
    emacs
    ffmpeg_7
    flyctl
    git-filter-repo
    git-lfs
    gitleaks
    gogcli
    google-cloud-sdk
    imagemagickBig
    kind
    kubernetes-helm-wrapped
    lazygit
    libpq
    librsvg
    livekit
    livekit-cli
    llmfit
    mactop
    minikube
    mint
    mise
    ngrok
    opencode-desktop
    javaPackages.compiler.openjdk25
    p7zip
    pandoc
    pipx
    poppler
    portaudio
    postgresql_14
    postgresql_16
    potrace
    redis
    resvg
    semgrep
    sox
    stow
    stripe-cli
    supabase-cli
    swiftformat
    swiftlint
    tailscale
    terraform
    time
    trivy
    universal-ctags
    warp-terminal
    websocat
    yazi-unwrapped
    yq
    yt-dlp
  ];

  fonts.packages = with pkgs; [
    berkeleyMono
    jetbrains-mono
    nerd-fonts.symbols-only
  ];
}
