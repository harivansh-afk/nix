{ config, ... }:
let
  theme = import ../lib/theme.nix { inherit config; };
in
{
  programs.bat = {
    enable = true;

    config = {
      theme = theme.batTheme theme.defaultMode;
    };
  };
}
