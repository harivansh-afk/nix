{ ... }:
{
  homebrew = {
    enable = true;

    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "uninstall";
    };

    taps = [
      "humanlayer/humanlayer"
      "mutagen-io/mutagen"
    ];

    brews = [
      "mutagen-io/mutagen/mutagen"
    ];

    casks = [
      "cap"
      "karabiner-elements"
      "rectangle"
      "raycast"
      "riptide-beta"
      "thebrowsercompany-dia"
      "wispr-flow"
    ];
  };
}
