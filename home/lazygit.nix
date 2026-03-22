{
  lib,
  pkgs,
  ...
}: {
  xdg.configFile."lazygit/config.yml".source = ../config/lazygit/config.yml;

  home.file = lib.mkIf pkgs.stdenv.isDarwin {
    "Library/Application Support/lazygit/config.yml".source =
      ../config/lazygit/config.yml;
  };
}
