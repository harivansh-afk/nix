{
  inputs,
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
    inputs.sops-nix.darwinModules.sops
    ../../modules/security/sops.nix
    ../../modules/users/darwin.nix
    ../../modules/apps/voiceink.nix
    ../../modules/apps/voiceink-dictionary.nix
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
      cleanup = "none";
    };

    taps = [
      "humanlayer/humanlayer"
    ];

    # CLI formulae. pngpaste is used by the `pasteimg` helper (dots/bin/pasteimg)
    # to reliably dump the clipboard image as PNG for the spark -> mac pull.
    brews = [
      "pngpaste"
    ];

    casks = [
      "cap"
      "ghostty"
      "helium-browser"
      "karabiner-elements"
      "raycast"
      "riptide-beta"
      # voiceink: built from source instead (free path); see
      # modules/apps/voiceink.nix. The cask is the paid distribution.
    ];
  };
}
