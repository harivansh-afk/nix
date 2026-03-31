{
  lib,
  hostConfig,
  ...
}:
{
  xdg.configFile."lazygit/config.yml".source = ../config/lazygit/config.yml;

  home.file = lib.mkIf hostConfig.isDarwin {
    "Library/Application Support/lazygit/config.yml".source = ../config/lazygit/config.yml;
  };
}
