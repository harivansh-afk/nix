{...}: {
  homebrew = {
    enable = true;

    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "none";
    };

    taps = [];

    brews = [];

    casks = [
      "cap"
      "raycast"
      "thebrowsercompany-dia"
      "wispr-flow"
    ];
  };
}
