# Homebrew (taps, formulae, casks) on the macbook, via nix-homebrew.
# Policy: every cask on this machine is declared here. cleanup is still
# "none" while the manual-install backlog (~30 apps in /Applications not yet
# adopted as casks) is worked through; the end state is cleanup = "zap" +
# HOMEBREW_BUNDLE_CLEANUP_NO_MAS=1 so this list becomes the single source of
# truth. Flip only after `brew bundle cleanup` (dry run) prints nothing you
# want to keep - zap also trashes app data dirs from the cask's zap stanza.
_: {
  homebrew = {
    enable = true;

    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "none";
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
    brews = [
      "pngpaste"
    ];

    casks = [
      "cap"
      "ghostty"
      "helium-browser"
      "humanlayer"
      "karabiner-elements"
      "periphery"
      "raycast"
      "riptide-beta"
      # T3 Code desktop app (auto_updates cask; the spark server is nix,
      # modules/services/t3code.nix).
      "t3-code"
      # Tailscale GUI (Standalone variant): the network extension IS the
      # tailnet node on this mac; see hosts/macbook/services.nix for why
      # nix-darwin's services.tailscale is deliberately not used.
      "tailscale-app"
      # Dia browser (was a manual-ish install; cask-owned since the audit).
      "thebrowsercompany-dia"
      # voiceink: built from source instead (free path); see
      # modules/apps/voiceink.nix. The cask is the paid distribution.
    ];
  };
}
