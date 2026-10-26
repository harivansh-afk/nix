{ homeDirectory, ... }:
let
  configHome = "${homeDirectory}/.config";
  stateHome = "${homeDirectory}/.local/state";
  defaultMode = "dark";
  themes = builtins.fromJSON (builtins.readFile ./palette.json);
  wallpapers = {
    dir = "${homeDirectory}/Pictures/Screensavers";
    dark = ../assets/wallpapers/solid-black.png;
    light = ../assets/wallpapers/solid-white.png;
    current = "${homeDirectory}/Pictures/Screensavers/wallpaper.png";
  };
  paths = {
    stateDir = "${stateHome}/theme";
    stateFile = "${stateHome}/theme/current";
    fzfDir = "${configHome}/fzf/themes";
    fzfCurrentFile = "${configHome}/fzf/themes/theme";
    ghosttyDir = "${configHome}/ghostty/themes";
    ghosttyCurrentFile = "${configHome}/ghostty/themes/cozybox-current";
    sketchybarDir = "${configHome}/sketchybar/themes";
    sketchybarCurrentFile = "${configHome}/sketchybar/themes/current";
  };

  renderGhostty =
    mode:
    let
      theme = themes.${mode};
      paletteLines = builtins.concatStringsSep "\n" (
        builtins.genList (index: "palette = ${toString index}=${builtins.elemAt theme.terminal index}") (
          builtins.length theme.terminal
        )
      );
    in
    ''
      background = ${theme.background}
      foreground = ${theme.foreground}
      cursor-color = ${theme.cursor}
      cursor-text = ${theme.background}
      selection-background = ${theme.selection}
      selection-foreground = ${theme.foreground}
      ${paletteLines}
    '';

  renderFzf =
    mode:
    let
      theme = themes.${mode};
      text = theme.text or theme.foreground;
    in
    ''
      --color=fg:${text},bg:${theme.background},hl:${theme.blue}
      --color=fg+:${text},bg+:${theme.surface},hl+:${theme.blue}
      --color=info:${theme.green},prompt:${theme.blue},pointer:${text},marker:${theme.green},spinner:${text}
    '';
  renderPurePrompt =
    mode:
    let
      t = themes.${mode};
      ansi = builtins.elemAt t.terminal;
      dirty = ansi (if mode == "light" then 3 else 11);
      identity = if mode == "light" then t.mutedText else t.foreground;
    in
    ''
      zstyle ':prompt:pure:path' color '${ansi 4}'
      zstyle ':prompt:pure:git:branch' color '${t.green}'
      zstyle ':prompt:pure:git:dirty' color '${dirty}'
      zstyle ':prompt:pure:git:arrow' color '${ansi (if mode == "light" then 5 else 13)}'
      zstyle ':prompt:pure:git:stash' color '${ansi (if mode == "light" then 6 else 14)}'
      zstyle ':prompt:pure:git:action' color '${dirty}'
      zstyle ':prompt:pure:prompt:success' color '${t.green}'
      zstyle ':prompt:pure:prompt:error' color '${t.red}'
      zstyle ':prompt:pure:execution_time' color '${ansi 8}'
      zstyle ':prompt:pure:host' color '${identity}'
      zstyle ':prompt:pure:user' color '${identity}'
      zstyle ':prompt:pure:user:root' color '${t.red}'
    '';

  batTheme = mode: if mode == "light" then "gruvbox-light" else "gruvbox-dark";

  renderSketchybar =
    mode:
    let
      t = themes.${mode};
      hex = color: builtins.replaceStrings [ "#" ] [ "0xff" ] color;
    in
    ''
      export BAR_COLOR=${hex t.barBackground}
      export SURFACE_COLOR=${hex t.surface}
      export SELECTED_COLOR=${hex t.selection}
      export TEXT_COLOR=${hex t.barForeground}
      export BRIGHT_COLOR=${hex t.barForeground}
      export MUTED_COLOR=${hex t.barForeground}
      export ACCENT_COLOR=${hex t.accent}
      export PINK_COLOR=${hex t.purple}
      export RED_COLOR=${hex t.red}
      export GREEN_COLOR=${hex t.green}
      export BORDER_COLOR=${hex t.barBorder}
    '';

  renderRex =
    mode:
    let
      t = themes.${mode};
      digits = {
        "0" = 0;
        "1" = 1;
        "2" = 2;
        "3" = 3;
        "4" = 4;
        "5" = 5;
        "6" = 6;
        "7" = 7;
        "8" = 8;
        "9" = 9;
        "a" = 10;
        "b" = 11;
        "c" = 12;
        "d" = 13;
        "e" = 14;
        "f" = 15;
      };
      channel =
        color: offset:
        let
          digit = index: digits.${builtins.substring index 1 color};
        in
        (digit offset * 16 + digit (offset + 1)) / 255.0;
      rgb = color: {
        colorSpace = "srgb";
        red = channel color 1;
        green = channel color 3;
        blue = channel color 5;
        alpha = 1;
      };
    in
    {
      id =
        if mode == "light" then
          "custom-E45EE8DD-F604-43CA-BEAF-AB0DD91BAF31"
        else
          "custom-AB1A406F-BC80-453C-BABD-D205D8B06585";
      name = if mode == "light" then "Cozybox-Light" else "Cozybox-Dark";
      appearance = mode;
      createdAt = 813167987.5234;
      source.ghosttyFile.fileName = "cozybox-${mode}";
      palette = {
        background = rgb t.background;
        foreground = rgb t.foreground;
        cursor = rgb t.cursor;
        cursorText = rgb t.background;
        selectionBackground = rgb t.selection;
        selectionForeground = rgb t.foreground;
        ansi = map rgb t.terminal;
      };
    };

  renderZshHighlights =
    mode:
    let
      t = themes.${mode};
      c = {
        arg0 = t.green;
        aqua = t.highlightAqua or (builtins.elemAt t.terminal 14);
        purple = t.highlightPurple or t.purple;
        yellow = t.highlightYellow or t.accent;
        text = t.text or t.foreground;
        comment = if mode == "light" then builtins.elemAt t.terminal 8 else t.mutedText;
        error = t.highlightError or t.red;
      };
      blueOrAqua = if mode == "light" then c.aqua else t.blue;
    in
    ''
      ZSH_HIGHLIGHT_STYLES[arg0]='fg=${c.arg0}'
      ZSH_HIGHLIGHT_STYLES[autodirectory]='fg=${c.arg0},underline'
      ZSH_HIGHLIGHT_STYLES[back-dollar-quoted-argument]='fg=${c.aqua}'
      ZSH_HIGHLIGHT_STYLES[back-double-quoted-argument]='fg=${c.aqua}'
      ZSH_HIGHLIGHT_STYLES[back-quoted-argument-delimiter]='fg=${c.purple}'
      ZSH_HIGHLIGHT_STYLES[bracket-error]='fg=${c.error},bold'
      ZSH_HIGHLIGHT_STYLES[bracket-level-1]='fg=${blueOrAqua},bold'
      ZSH_HIGHLIGHT_STYLES[bracket-level-2]='fg=${c.arg0},bold'
      ZSH_HIGHLIGHT_STYLES[bracket-level-3]='fg=${c.purple},bold'
      ZSH_HIGHLIGHT_STYLES[bracket-level-4]='fg=${c.yellow},bold'
      ZSH_HIGHLIGHT_STYLES[bracket-level-5]='fg=${c.aqua},bold'
      ZSH_HIGHLIGHT_STYLES[comment]='fg=${c.comment}'
      ZSH_HIGHLIGHT_STYLES[command-substitution-delimiter]='fg=${c.purple}'
      ZSH_HIGHLIGHT_STYLES[dollar-double-quoted-argument]='fg=${c.aqua}'
      ZSH_HIGHLIGHT_STYLES[dollar-quoted-argument]='fg=${c.yellow}'
      ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=${c.yellow}'
      ZSH_HIGHLIGHT_STYLES[global-alias]='fg=${c.aqua}'
      ZSH_HIGHLIGHT_STYLES[globbing]='fg=${blueOrAqua}'
      ZSH_HIGHLIGHT_STYLES[history-expansion]='fg=${blueOrAqua}'
      ZSH_HIGHLIGHT_STYLES[path]='fg=${c.text},underline'
      ZSH_HIGHLIGHT_STYLES[precommand]='fg=${c.arg0},underline'
      ZSH_HIGHLIGHT_STYLES[process-substitution-delimiter]='fg=${c.purple}'
      ZSH_HIGHLIGHT_STYLES[rc-quote]='fg=${c.aqua}'
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
    paths
    renderFzf
    renderGhostty
    renderPurePrompt
    renderRex
    renderSketchybar
    renderZshHighlights
    wallpapers
    ;
}
