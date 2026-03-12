{...}: {
  homebrew = {
    enable = true;

    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "none";
    };

    taps = [
      "humanlayer/humanlayer"
      "jnsahaj/lumen"
      "nicosuave/tap"
      "pantsbuild/tap"
      "steipete/tap"
      "withgraphite/tap"
    ];

    brews = [
      "daytonaio/tap/daytona"
      "jnsahaj/lumen/lumen"
      "nicosuave/tap/memex"
      "postgresql@17"
      "python@3.13"
      "withgraphite/tap/graphite"
      "worktrunk"
    ];

    casks = [
      "anaconda"
      "pants"
      "riptide-dev"
    ];
  };
}
