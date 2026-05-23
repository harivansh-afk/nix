{
  pkgs,
  lib,
  theme,
  ...
}:
{
  packages = [ pkgs.fzf ];

  files.".config/fzf/themes/cozybox-dark".text = theme.renderFzf "dark";
  files.".config/fzf/themes/cozybox-light".text = theme.renderFzf "light";

  sessionVars.FZF_DEFAULT_OPTS_FILE = theme.paths.fzfCurrentFile;

  zshInit = lib.mkOrder 850 ''
    source ${pkgs.fzf}/share/fzf/key-bindings.zsh
    source ${pkgs.fzf}/share/fzf/completion.zsh
  '';
}
