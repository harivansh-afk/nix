{config, ...}: let
  defaultMode = "dark";
  paths = {
    stateDir = "${config.xdg.stateHome}/theme";
    stateFile = "${config.xdg.stateHome}/theme/current";
    ghosttyDir = "${config.xdg.configHome}/ghostty/themes";
    ghosttyCurrentFile = "${config.xdg.configHome}/ghostty/themes/current.conf";
    tmuxDir = "${config.xdg.configHome}/tmux/theme";
    tmuxCurrentFile = "${config.xdg.configHome}/tmux/theme/current.conf";
  };

  themes = {
    dark = {
      ghosttyTheme = "Gruvbox Material Dark";
      background = "#181818";
      surface = "#1e1e1e";
      selectionBackground = "#504945";
      selectionForeground = "#ebdbb2";
      cursorColor = "#ddc7a1";
      text = "#d4be98";
      mutedText = "#7c6f64";
      red = "#ea6962";
      green = "#8ec97c";
      yellow = "#d8a657";
      blue = "#5b84de";
      aqua = "#8ec07c";
      purple = "#d3869b";
      orange = "#e78a4e";
      border = "#181818";
    };

    light = {
      ghosttyTheme = "Gruvbox Material Light";
      background = "#e7e7e7";
      surface = "#e1e1e1";
      selectionBackground = "#c3c7c9";
      selectionForeground = "#1d2021";
      cursorColor = "#282828";
      text = "#282828";
      mutedText = "#665c54";
      red = "#ea6962";
      green = "#8ec97c";
      yellow = "#d8a657";
      blue = "#5b84de";
      aqua = "#8ec07c";
      purple = "#d3869b";
      orange = "#e78a4e";
      border = "#c3c7c9";
    };
  };

  renderGhostty = mode: let
    theme = themes.${mode};
  in ''
    theme = "${theme.ghosttyTheme}"
    background = ${theme.background}
    cursor-color = ${theme.cursorColor}
    selection-background = ${theme.selectionBackground}
    selection-foreground = ${theme.selectionForeground}
    palette = 1=${theme.red}
    palette = 2=${theme.green}
    palette = 3=${theme.yellow}
    palette = 4=${theme.blue}
    palette = 5=${theme.purple}
    palette = 6=${theme.aqua}
    palette = 9=${theme.red}
    palette = 10=${theme.green}
    palette = 11=${theme.yellow}
    palette = 12=${theme.blue}
    palette = 13=${theme.purple}
    palette = 14=${theme.aqua}
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
in {
  inherit defaultMode paths renderGhostty renderTmux themes;
}
