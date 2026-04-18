{ ... }:
{
  homebrew = {
    enable = true;

    onActivation = {
      autoUpdate = false;
      upgrade = false;
      # `brew bundle --cleanup` is by far the slowest part of darwin activation
      # on this machine. Keep switches fast and do cleanup manually when needed.
      cleanup = "none";
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
      "helium-browser"
      "karabiner-elements"
      "rectangle"
      "raycast"
      "riptide-beta"
      "thebrowsercompany-dia"
      "wispr-flow"
    ];
  };
}
