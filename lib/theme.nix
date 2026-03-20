{config, ...}: let
  defaultMode = "dark";
  paths = {
    stateDir = "${config.xdg.stateHome}/theme";
    stateFile = "${config.xdg.stateHome}/theme/current";
    fzfDir = "${config.xdg.configHome}/fzf/themes";
    fzfCurrentFile = "${config.xdg.configHome}/fzf/themes/theme";
    ghosttyDir = "${config.xdg.configHome}/ghostty/themes";
    ghosttyCurrentFile = "${config.xdg.configHome}/ghostty/themes/cozybox-current";
    tmuxDir = "${config.xdg.configHome}/tmux/theme";
    tmuxCurrentFile = "${config.xdg.configHome}/tmux/theme/current.conf";
  };

  themes = {
    dark = {
      background = "#181818";
      surface = "#1e1e1e";
      selectionBackground = "#504945";
      selectionForeground = "#ebdbb2";
      cursorColor = "#ddc7a1";
      cursorText = "#181818";
      foreground = "#ebdbb2";
      text = "#d4be98";
      mutedText = "#7c6f64";
      blue = "#5b84de";
      green = "#8ec97c";
      purple = "#d3869b";
      border = "#181818";
      palette = [
        "#1d2021"
        "#ea6962"
        "#8ec97c"
        "#d79921"
        "#5b84de"
        "#b16286"
        "#689d6a"
        "#a89984"
        "#928374"
        "#ea6962"
        "#8ec97c"
        "#fabd2f"
        "#5b84de"
        "#d3869b"
        "#8ec07c"
        "#ebdbb2"
      ];
    };

    light = {
      background = "#e7e7e7";
      surface = "#e1e1e1";
      selectionBackground = "#c3c7c9";
      selectionForeground = "#3c3836";
      cursorColor = "#282828";
      cursorText = "#e7e7e7";
      foreground = "#3c3836";
      text = "#3c3836";
      mutedText = "#665c54";
      blue = "#076678";
      green = "#427b58";
      purple = "#d3869b";
      border = "#e7e7e7";
      palette = [
        "#f9f5d7"
        "#ea6962"
        "#8ec97c"
        "#d8a657"
        "#5b84de"
        "#d3869b"
        "#8ec07c"
        "#7c6f64"
        "#928374"
        "#ea6962"
        "#8ec97c"
        "#d8a657"
        "#5b84de"
        "#d3869b"
        "#8ec07c"
        "#3c3836"
      ];
    };
  };

  renderGhostty = mode: let
    theme = themes.${mode};
    paletteLines =
      builtins.concatStringsSep "\n"
      (builtins.genList
        (index: "palette = ${toString index}=${builtins.elemAt theme.palette index}")
        (builtins.length theme.palette));
  in ''
    background = ${theme.background}
    foreground = ${theme.foreground}
    cursor-color = ${theme.cursorColor}
    cursor-text = ${theme.cursorText}
    selection-background = ${theme.selectionBackground}
    selection-foreground = ${theme.selectionForeground}
    ${paletteLines}
  '';

  renderTmux = mode: let
    theme = themes.${mode};
  in ''
    set-option -g @cozybox-mode '${mode}'
    set-option -g @cozybox-accent '${theme.purple}'
    set-option -g status-style bg=${theme.background},fg=${theme.text}
    set-option -g window-status-format " #I#[fg=${theme.purple}]:#[fg=default]#W "
    set-option -g window-status-current-format " #[fg=${theme.purple}]*#[fg=default]#I#[fg=${theme.purple}]:#[fg=default]#W "
    set-option -g window-status-separator ""
    set-option -g pane-border-style fg=${theme.border}
    set-option -g pane-active-border-style fg=${theme.border}
  '';

  renderFzf = mode: let
    theme = themes.${mode};
  in ''
    --color=fg:${theme.text},bg:${theme.background},hl:${theme.blue}
    --color=fg+:${theme.text},bg+:${theme.surface},hl+:${theme.blue}
    --color=info:${theme.green},prompt:${theme.blue},pointer:${theme.text},marker:${theme.green},spinner:${theme.text}
  '';
in {
  inherit defaultMode paths renderFzf renderGhostty renderTmux themes;
}
