{
  pkgs,
  self,
  username,
  hostname,
  ...
}:
{
  imports = [
    ../../system/common.nix
    ../../system/packages.nix
    ./macos.nix
  ];

  networking.hostName = hostname;

  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
    shell = pkgs.zsh;
  };

  system.primaryUser = username;
  system.configurationRevision = self.rev or self.dirtyRev or null;
  system.stateVersion = 6;

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
