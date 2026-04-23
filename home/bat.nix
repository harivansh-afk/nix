{ ... }:
{
  # Theme is set at runtime via $BAT_THEME (see home/zsh.nix) so that
  # `theme light` / `theme dark` switches bat without a rebuild.
  programs.bat = {
    enable = true;
  };
}
