{inputs, ...}: {
  imports = [
    ./common.nix
    ./colima.nix
    ./karabiner.nix
    ./rectangle.nix
    inputs.vimessage.homeManagerModules.default
  ];

  programs.vimessage = {
    enable = true;
    mod = "ctrl";
  };
}
