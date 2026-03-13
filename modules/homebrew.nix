{...}: {
  homebrew = {
    enable = true;

    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "uninstall";
    };

    taps = [
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
