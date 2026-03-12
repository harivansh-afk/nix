{...}: {
  homebrew = {
    enable = true;

    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "none";
    };

    taps = [
      "daytonaio/tap"
      "getcompanion-ai/tap"
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
      "steipete/tap/bird"
      "steipete/tap/summarize"
      "withgraphite/tap/graphite"
      "worktrunk"
    ];

    casks = [
      "anaconda"
      "codelayer"
      "codexbar"
      "companion"
      "osaurus"
      "pants"
      "riptide-beta"
      "riptide-dev"
      "riptide-experimental"
      "virtualbox"
    ];
  };
}
