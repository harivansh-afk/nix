{...}: {
  homebrew = {
    enable = true;

    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "uninstall";
    };

    taps = [];

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
