{...}: {
  homebrew = {
    enable = true;

    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "none";
    };

    taps = [
      "nicosuave/tap"
      "withgraphite/tap"
    ];

    brews = [
      "nicosuave/tap/memex"
      "postgresql@17"
      "python@3.13"
      "withgraphite/tap/graphite"
      "worktrunk"
    ];

    casks = [
      "cap"
      "raycast"
      "thebrowsercompany-dia"
      "wispr-flow"
    ];
  };
}
