{ theme, ... }:
{
  home.sessionVariables.FZF_DEFAULT_OPTS_FILE = theme.paths.fzfCurrentFile;
  xdg.configFile."fzf/themes/cozybox-dark".text = theme.renderFzf "dark";
  xdg.configFile."fzf/themes/cozybox-light".text = theme.renderFzf "light";
}
