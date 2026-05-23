{
  lib,
  hostConfig,
  pkgs,
  theme,
  ...
}:
let
  baseConfig = builtins.readFile ../../../dots/lazygit/config.yml;
  mkFullConfig = mode: baseConfig + theme.renderLazygit mode;
  darwinFiles = {
    "Library/Application Support/lazygit/config-dark.yml".text = mkFullConfig "dark";
    "Library/Application Support/lazygit/config-light.yml".text = mkFullConfig "light";
  };
in
{
  packages = [ pkgs.lazygit ];

  files = {
    ".config/lazygit/config-dark.yml".text = mkFullConfig "dark";
    ".config/lazygit/config-light.yml".text = mkFullConfig "light";
  }
  // (if hostConfig.isDarwin then darwinFiles else { });
}
