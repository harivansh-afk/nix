{
  lib,
  hostConfig,
  theme,
  ...
}:
let
  baseConfig = builtins.readFile ../dots/lazygit/config.yml;
  mkFullConfig = mode: baseConfig + theme.renderLazygit mode;
in
{
  xdg.configFile."lazygit/config-dark.yml".text = mkFullConfig "dark";
  xdg.configFile."lazygit/config-light.yml".text = mkFullConfig "light";

  home.file = lib.mkIf hostConfig.isDarwin {
    "Library/Application Support/lazygit/config-dark.yml".text = mkFullConfig "dark";
    "Library/Application Support/lazygit/config-light.yml".text = mkFullConfig "light";
  };
}
