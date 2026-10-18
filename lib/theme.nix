# Theme palette and per-app renderers. Takes the user's home directory
# instead of a home-manager config: every consumer (pkgs/scripts/default.nix,
# modules/users/*) passes the target user's homeDirectory explicitly, and
# the XDG paths are derived from it (both platforms use the default
# ~/.config and ~/.local/state locations).
{ homeDirectory, ... }:
let
  configHome = "${homeDirectory}/.config";
  stateHome = "${homeDirectory}/.local/state";
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

  themes = {
    dark = {
      background = "#101010";
      surface = "#161616";
      selectionBackground = "#504945";
      selectionForeground = "#ebdbb2";
      cursorColor = "#ddc7a1";
      cursorText = "#101010";
      foreground = "#ebdbb2";
      text = "#d4be98";
      mutedText = "#7c6f64";
      inherit (sharedPalette) blue;
      inherit (sharedPalette) green;
      inherit (sharedPalette) purple;
      border = "#3c3836";
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
      inherit (sharedPalette) blue;
      green = "#427b58";
      inherit (sharedPalette) purple;
      border = "#000000";
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

  batTheme = mode: if mode == "light" then "gruvbox-light" else "gruvbox-dark";

  renderSketchybar =
    mode:
    let
      t = themes.${mode};
      accent = if mode == "light" then "#b57614" else sharedPalette.yellow;
      red = if mode == "light" then "#c5524a" else sharedPalette.red;
      hex = color: builtins.replaceStrings [ "#" ] [ "0xff" ] color;
    in
    ''
      export BAR_COLOR=0xff000000
      export SURFACE_COLOR=${hex t.surface}
      export SELECTED_COLOR=${hex t.selectionBackground}
      export TEXT_COLOR=0xffffffff
      export BRIGHT_COLOR=0xffffffff
      export MUTED_COLOR=0xffffffff
      export ACCENT_COLOR=${hex accent}
      export PINK_COLOR=${hex t.purple}
      export RED_COLOR=${hex red}
      export GREEN_COLOR=${hex t.green}
      export BORDER_COLOR=0xff666666
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
        cursor = rgb t.cursorColor;
        cursorText = rgb t.cursorText;
        selectionBackground = rgb t.selectionBackground;
        selectionForeground = rgb t.selectionForeground;
        ansi = map rgb t.palette;
      };
    };

  renderZshHighlights =
    mode:
    let
      light = {
        arg0 = "#427b58";
        aqua = "#076678";
        purple = "#8f3f71";
        yellow = "#b57614";
        text = "#3c3836";
        comment = "#928374";
        error = "#ea6962";
      };
      dark = {
        arg0 = sharedPalette.green;
        inherit (sharedPalette) aqua;
        inherit (sharedPalette) purple;
        yellow = "#d8a657";
        text = "#d4be98";
        comment = "#7c6f64";
        error = sharedPalette.red;
        inherit (sharedPalette) blue;
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
    paths
    renderFzf
    renderGhostty
    renderPurePrompt
    renderRex
    renderSketchybar
    renderZshHighlights
    themes
    wallpapers
    ;
}
