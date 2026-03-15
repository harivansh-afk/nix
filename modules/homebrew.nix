{...}: {
  homebrew = {
    enable = true;

    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "uninstall";
    };

    taps = [
      # riptide-dev is still sourced from this tap.
      "humanlayer/humanlayer"
    ];

    brews = [
      "bitwarden-cli"
    ];

    casks = [
      "cap"
      "codex"
      "rectangle"
      "raycast"
      "riptide-dev"
      "thebrowsercompany-dia"
      "wispr-flow"
    ];
  };
}
