{ homeDirectory }:
{
  inherit homeDirectory;
  xdg = {
    configHome = "${homeDirectory}/.config";
    stateHome = "${homeDirectory}/.local/state";
    dataHome = "${homeDirectory}/.local/share";
    cacheHome = "${homeDirectory}/.cache";
  };
}
