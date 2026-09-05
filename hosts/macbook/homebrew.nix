# Homebrew via nix-homebrew. `cleanup = "zap"` makes this list the cask state
# of the machine; anything installed and not declared is removed on switch.
# Manual installs brew does not own (Raycast Beta, Docker) are never touched.
{ lib, username, ... }:
let
  # Homebrew 6 requires trusted taps and the Brewfile `trusted:` flag does
  # not persist, so preActivation writes the trust store too.
  trustedTaps = [
    "humanlayer/humanlayer"
    "peripheryapp/periphery"
  ];
in
{
  system.activationScripts.preActivation.text = lib.mkAfter ''
    if [ -x /opt/homebrew/bin/brew ]; then
      for tap in ${toString trustedTaps}; do
        sudo -u ${username} /opt/homebrew/bin/brew trust "$tap" >/dev/null 2>&1 || true
      done
    fi
  '';

  homebrew = {
    enable = true;

    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "zap";
      extraEnv.HOMEBREW_BUNDLE_CLEANUP_NO_MAS = "1";
    };

    taps = map (name: {
      inherit name;
      trusted = true;
    }) trustedTaps;

    brews = [
      "pngpaste"
    ];

    # No voiceink: the cask is the paid build, ./voiceink builds the free one.
    casks = [
      "beeper"
      "cap"
      "chatgpt"
      "claude"
      "codex"
      "ghostty"
      "granola"
      "helium-browser"
      "humanlayer"
      "karabiner-elements"
      "linear"
      "markdown-preview"
      "riptide-beta"
      "signal"
      "slack"
      "superhuman"
      "tailscale-app"
      "thebrowsercompany-dia"
    ];
  };
}
