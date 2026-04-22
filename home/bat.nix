{ theme, ... }:
{
  programs.bat = {
    enable = true;
    config.theme = theme.batTheme theme.defaultMode;
  };
}
