{
  pkgs,
  lib,
  hostConfig,
  ...
}:
let
  settings = {
    custom_cpu_name = hostConfig.hostname;
    color_theme = "ayu";
    theme_background = false;
    vim_keys = true;
    rounded_corners = false;
  };
  formatValue =
    v:
    if v == true then
      "True"
    else if v == false then
      "False"
    else if builtins.isInt v then
      toString v
    else
      "\"${toString v}\"";
  configText = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (k: v: "${k} = ${formatValue v}") settings
  );
in
{
  packages = [ pkgs.btop ];
  files.".config/btop/btop.conf".text = configText + "\n";
}
