{ config, ... }:
let
  defaultMode = "dark";
  sharedPalette = {
    red = "#ea6962";
    green = "#8ec97c";
    yellow = "#d79921";
    yellowBright = "#fabd2f";
    blue = "#5b84de";
    purple = "#d3869b";
    purpleNeutral = "#b16286";
    aqua = "#8ec07c";
    aquaNeutral = "#689d6a";
    gray = "#928374";
  };
  wallpaperGeneration =
    let
      viewPresets = {
        close = 12;
        balanced = 11;
        wide = 10;
      };
      densityPresets = {
        sparse = 14;
        balanced = 20;
        dense = 28;
      };
      view = "balanced";
      density = "balanced";
      candidatePool = {
        maxCached = 24;
        randomAttempts = 20;
        historySize = 10;
      };
      label = {
        enabled = true;
        fontSize = 14;
      };
    in
    {
      inherit
        candidatePool
        density
        label
        view
        ;
      presetValues = {
        density = densityPresets;
        view = viewPresets;
      };
      resolved = {
        candidatePool = candidatePool;
        contours = {
          levels = densityPresets.${density};
        };
        label = label;
        view = {
          tileConcurrency = 6;
          zoom = viewPresets.${view};
        };
      };
    };
  wallpapers = {
    dir = "${config.home.homeDirectory}/Pictures/Screensavers";
    dark = "${config.home.homeDirectory}/Pictures/Screensavers/wallpaper-dark.jpg";
    light = "${config.home.homeDirectory}/Pictures/Screensavers/wallpaper-light.jpg";
    current = "${config.home.homeDirectory}/Pictures/Screensavers/wallpaper.jpg";
    staticDark = ../assets/wallpapers/topography-dark.jpg;
    staticLight = ../assets/wallpapers/topography-light.jpg;
    generation = wallpaperGeneration;
  };
  paths = {
    stateDir = "${config.xdg.stateHome}/theme";
    stateFile = "${config.xdg.stateHome}/theme/current";
    fzfDir = "${config.xdg.configHome}/fzf/themes";
    fzfCurrentFile = "${config.xdg.configHome}/fzf/themes/theme";
    ghosttyDir = "${config.xdg.configHome}/ghostty/themes";
    ghosttyCurrentFile = "${config.xdg.configHome}/ghostty/themes/cozybox-current";
    tmuxDir = "${config.xdg.configHome}/tmux/theme";
    tmuxCurrentFile = "${config.xdg.configHome}/tmux/theme/current.conf";
    lazygitDir = "${config.xdg.configHome}/lazygit";
    lazygitCurrentFile = "${config.xdg.configHome}/lazygit/config.yml";
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
      blue = sharedPalette.blue;
      green = sharedPalette.green;
      purple = sharedPalette.purple;
      border = "#181818";
      palette = [
        "#1d2021"
        sharedPalette.red
        sharedPalette.green
        sharedPalette.yellow
        sharedPalette.blue
        sharedPalette.purpleNeutral
        sharedPalette.aquaNeutral
        "#a89984"
        sharedPalette.gray
        sharedPalette.red
        sharedPalette.green
        sharedPalette.yellowBright
        sharedPalette.blue
        sharedPalette.purple
        sharedPalette.aqua
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
      blue = sharedPalette.blue;
      green = "#427b58";
      purple = sharedPalette.purple;
      border = "#e7e7e7";
      palette = [
        "#f9f5d7"
        "#c5524a"
        "#427b58"
        sharedPalette.yellow
        "#4261a5"
        sharedPalette.purpleNeutral
        sharedPalette.aquaNeutral
        "#7c6f64"
        sharedPalette.gray
        "#c5524a"
        "#427b58"
        sharedPalette.yellowBright
        "#4261a5"
        sharedPalette.purple
        sharedPalette.aqua
        "#3c3836"
      ];
    };
  };

  renderGhostty =
    mode:
    let
      theme = themes.${mode};
      paletteLines = builtins.concatStringsSep "\n" (
        builtins.genList (index: "palette = ${toString index}=${builtins.elemAt theme.palette index}") (
          builtins.length theme.palette
        )
      );
    in
    ''
      background = ${theme.background}
      foreground = ${theme.foreground}
      cursor-color = ${theme.cursorColor}
      cursor-text = ${theme.cursorText}
      selection-background = ${theme.selectionBackground}
      selection-foreground = ${theme.selectionForeground}
      ${paletteLines}
    '';

  renderTmux =
    mode:
    let
      theme = themes.${mode};
    in
    ''
      set-option -g @cozybox-mode '${mode}'
      set-option -g @cozybox-accent '${theme.purple}'
      set-option -g status-style bg=${theme.background},fg=${theme.text}
      set-option -g window-status-format " #I#[fg=${theme.purple}]:#[fg=default]#W "
      set-option -g window-status-current-format " #[fg=${theme.purple}]*#[fg=default]#I#[fg=${theme.purple}]:#[fg=default]#W "
      set-option -g window-status-separator ""
      set-option -g pane-border-style fg=${theme.border}
      set-option -g pane-active-border-style fg=${theme.border}
    '';

  renderFzf =
    mode:
    let
      theme = themes.${mode};
    in
    ''
      --color=fg:${theme.text},bg:${theme.background},hl:${theme.blue}
      --color=fg+:${theme.text},bg+:${theme.surface},hl+:${theme.blue}
      --color=info:${theme.green},prompt:${theme.blue},pointer:${theme.text},marker:${theme.green},spinner:${theme.text}
    '';
  renderPurePrompt =
    mode:
    let
      theme = themes.${mode};
      c =
        if mode == "light" then
          {
            path = "#4261a5";
            branch = "#427b58";
            dirty = sharedPalette.yellow;
            arrow = sharedPalette.purpleNeutral;
            stash = sharedPalette.aquaNeutral;
            success = "#427b58";
            error = "#c5524a";
            execTime = sharedPalette.gray;
            host = "#665c54";
            user = "#665c54";
          }
        else
          {
            path = sharedPalette.blue;
            branch = sharedPalette.green;
            dirty = sharedPalette.yellowBright;
            arrow = sharedPalette.purple;
            stash = sharedPalette.aqua;
            success = sharedPalette.green;
            error = sharedPalette.red;
            execTime = sharedPalette.gray;
            host = "#ebdbb2";
            user = "#ebdbb2";
          };
    in
    ''
      zstyle ':prompt:pure:path' color '${c.path}'
      zstyle ':prompt:pure:git:branch' color '${c.branch}'
      zstyle ':prompt:pure:git:dirty' color '${c.dirty}'
      zstyle ':prompt:pure:git:arrow' color '${c.arrow}'
      zstyle ':prompt:pure:git:stash' color '${c.stash}'
      zstyle ':prompt:pure:git:action' color '${c.dirty}'
      zstyle ':prompt:pure:prompt:success' color '${c.success}'
      zstyle ':prompt:pure:prompt:error' color '${c.error}'
      zstyle ':prompt:pure:execution_time' color '${c.execTime}'
      zstyle ':prompt:pure:host' color '${c.host}'
      zstyle ':prompt:pure:user' color '${c.user}'
      zstyle ':prompt:pure:user:root' color '${c.error}'
    '';

  renderLazygit =
    mode:
    let
      c =
        if mode == "light" then
          {
            activeBorder = "#427b58";
            inactiveBorder = "#c3c7c9";
            selectedLineBg = "#e1e1e1";
            optionsText = "#b57614";
            selectedRangeBg = "#c3c7c9";
            cherryPickedBg = "#427b58";
            cherryPickedFg = "#e7e7e7";
            unstaged = "#c5524a";
            defaultFg = "#3c3836";
          }
        else
          {
            activeBorder = "#b8bb26";
            inactiveBorder = "#504945";
            selectedLineBg = "#3c3836";
            optionsText = "#fabd2f";
            selectedRangeBg = "#504945";
            cherryPickedBg = "#689d6a";
            cherryPickedFg = "#282828";
            unstaged = "#fb4934";
            defaultFg = "#ebdbb2";
          };
    in
    ''
      gui:
        theme:
          activeBorderColor:
            - "${c.activeBorder}"
            - bold
          inactiveBorderColor:
            - "${c.inactiveBorder}"
          selectedLineBgColor:
            - "${c.selectedLineBg}"
          optionsTextColor:
            - "${c.optionsText}"
          selectedRangeBgColor:
            - "${c.selectedRangeBg}"
          cherryPickedCommitBgColor:
            - "${c.cherryPickedBg}"
          cherryPickedCommitFgColor:
            - "${c.cherryPickedFg}"
          unstagedChangesColor:
            - "${c.unstaged}"
          defaultFgColor:
            - "${c.defaultFg}"
    '';

  batTheme = mode: if mode == "light" then "gruvbox-light" else "gruvbox-dark";

  deltaTheme = mode: if mode == "light" then "gruvbox-light" else "gruvbox-dark";

  renderZshHighlights =
    mode:
    let
      # Light mode uses gruvbox-light specific colors
      light = {
        arg0 = "#427b58";
        aqua = "#076678";
        purple = "#8f3f71";
        yellow = "#b57614";
        text = "#3c3836";
        comment = "#928374";
        error = "#ea6962";
      };
      # Dark mode uses our theme palette
      dark = {
        arg0 = sharedPalette.green;
        aqua = sharedPalette.aqua;
        purple = sharedPalette.purple;
        yellow = "#d8a657";
        text = "#d4be98";
        comment = "#7c6f64";
        error = sharedPalette.red;
        blue = sharedPalette.blue;
      };
      c = if mode == "light" then light else dark;
      blueOrAqua = if mode == "light" then c.aqua else c.blue;
    in
    ''
      ZSH_HIGHLIGHT_STYLES[arg0]='fg=${c.arg0}'
      ZSH_HIGHLIGHT_STYLES[autodirectory]='fg=${c.arg0},underline'
      ZSH_HIGHLIGHT_STYLES[back-dollar-quoted-argument]='fg=${if mode == "light" then c.aqua else c.aqua}'
      ZSH_HIGHLIGHT_STYLES[back-double-quoted-argument]='fg=${if mode == "light" then c.aqua else c.aqua}'
      ZSH_HIGHLIGHT_STYLES[back-quoted-argument-delimiter]='fg=${c.purple}'
      ZSH_HIGHLIGHT_STYLES[bracket-error]='fg=${c.error},bold'
      ZSH_HIGHLIGHT_STYLES[bracket-level-1]='fg=${blueOrAqua},bold'
      ZSH_HIGHLIGHT_STYLES[bracket-level-2]='fg=${c.arg0},bold'
      ZSH_HIGHLIGHT_STYLES[bracket-level-3]='fg=${c.purple},bold'
      ZSH_HIGHLIGHT_STYLES[bracket-level-4]='fg=${c.yellow},bold'
      ZSH_HIGHLIGHT_STYLES[bracket-level-5]='fg=${if mode == "light" then c.aqua else c.aqua},bold'
      ZSH_HIGHLIGHT_STYLES[comment]='fg=${c.comment}'
      ZSH_HIGHLIGHT_STYLES[command-substitution-delimiter]='fg=${c.purple}'
      ZSH_HIGHLIGHT_STYLES[dollar-double-quoted-argument]='fg=${
        if mode == "light" then c.aqua else c.aqua
      }'
      ZSH_HIGHLIGHT_STYLES[dollar-quoted-argument]='fg=${c.yellow}'
      ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=${c.yellow}'
      ZSH_HIGHLIGHT_STYLES[global-alias]='fg=${if mode == "light" then c.aqua else c.aqua}'
      ZSH_HIGHLIGHT_STYLES[globbing]='fg=${blueOrAqua}'
      ZSH_HIGHLIGHT_STYLES[history-expansion]='fg=${blueOrAqua}'
      ZSH_HIGHLIGHT_STYLES[path]='fg=${c.text},underline'
      ZSH_HIGHLIGHT_STYLES[precommand]='fg=${c.arg0},underline'
      ZSH_HIGHLIGHT_STYLES[process-substitution-delimiter]='fg=${c.purple}'
      ZSH_HIGHLIGHT_STYLES[rc-quote]='fg=${if mode == "light" then c.aqua else c.aqua}'
      ZSH_HIGHLIGHT_STYLES[redirection]='fg=${c.yellow}'
      ZSH_HIGHLIGHT_STYLES[reserved-word]='fg=${c.yellow}'
      ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg=${c.yellow}'
      ZSH_HIGHLIGHT_STYLES[suffix-alias]='fg=${c.arg0},underline'
      ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=${c.error},bold'
    '';
in
{
  inherit
    batTheme
    defaultMode
    deltaTheme
    paths
    renderFzf
    renderGhostty
    renderLazygit
    renderPurePrompt
    renderTmux
    renderZshHighlights
    themes
    wallpapers
    ;
}
