# Homebrew (taps, formulae, casks) on the macbook, via nix-homebrew.
# This list IS the machine's cask state: cleanup = "zap" uninstalls (and
# purges the zap stanza of) anything installed but not declared here, so
# adding/removing a GUI app is an edit + switch. Mac App Store apps are
# excluded from cleanup (HOMEBREW_BUNDLE_CLEANUP_NO_MAS) since no masApps
# are declared. Manual /Applications installs that brew does not own are
# never touched: Raycast Beta (no cask exists; self-updates) and Docker.app
# (adoption fails on macOS app-protection while it runs, and a forced
# reinstall re-does the privileged helper; it self-updates). VoiceInk and
# Mux.app are built from source (modules/apps/voiceink.nix, ~/Documents/Git/mux).
_: {
  homebrew = {
    enable = true;

    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "zap";
      extraEnv.HOMEBREW_BUNDLE_CLEANUP_NO_MAS = "1";
    };

    # Third-party taps must be trusted: Homebrew 6 enables
    # HOMEBREW_REQUIRE_TAP_TRUST by default and aborts activation when a
    # Brewfile references an untrusted tap's cask (hit live with periphery).
    taps = [
      {
        name = "can1357/tap"; # riptide-beta
        trusted = true;
      }
      {
        name = "humanlayer/humanlayer";
        trusted = true;
      }
      {
        name = "peripheryapp/periphery";
        trusted = true;
      }
    ];

    # CLI formulae. pngpaste is used by the `pasteimg` helper (dots/bin/pasteimg)
    # to reliably dump the clipboard image as PNG for the spark -> mac pull.
    # NEVER `omp` here: omp is installer-managed in ~/.local/bin (CLAUDE.md);
    # a brew omp shadows it on PATH (removed 2026-08-21 after exactly that).
    # CLI tools otherwise live in nix (packages.nix), not brew.
    brews = [
      "pngpaste"
    ];

    casks = [
      "beeper"
      "cap"
      "chatgpt"
      "claude"
      "codex"
      "conductor"
      "ghostty"
      "granola"
      "helium-browser"
      "humanlayer"
      "karabiner-elements"
      "linear"
      "minecraft"
      "opencode-desktop"
      "periphery"
      "riptide-beta"
      "screen-studio"
      "signal"
      "slack"
      "stolendata-mpv"
      "superhuman"
      "tailscale-app"
      "telegram"
      "thebrowsercompany-dia"
      "typora"
      "visual-studio-code"
      "zed"
      # voiceink: built from source instead (free path); see
      # modules/apps/voiceink.nix. The cask is the paid distribution.
    ];
  };
}
