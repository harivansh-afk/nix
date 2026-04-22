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
    ];

    casks = [
      "cap"
      "ghostty"
      "helium-browser"
      "karabiner-elements"
      "raycast"
      "riptide-beta"
      "wispr-flow"
    ];
  };
}
