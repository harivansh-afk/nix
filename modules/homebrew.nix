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

    brews = [];

    casks = [
      "cap"
      "raycast"
      "riptide-dev"
      "thebrowsercompany-dia"
      "wispr-flow"
    ];
  };
}
