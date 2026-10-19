{ lib, username, ... }:
let

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
      "logi-options+"
      "markdown-preview"
      "signal"
      "slack"
      "tailscale-app"
      "thebrowsercompany-dia"
    ];
  };
}
