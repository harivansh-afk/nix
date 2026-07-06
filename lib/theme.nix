# Theme palette and per-app renderers. Takes the user's home directory
# instead of a home-manager config: every consumer (scripts/default.nix,
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
  wallpaperGeneration =
    let
      viewPresets = {
        close = 12;
        balanced = 11;
        wide = 10;
        ultrawide = 9;
      };
      densityPresets = {
        sparse = 14;
        balanced = 20;
        dense = 28;
        packed = 40;
      };
      view = "wide";
      density = "dense";
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
        inherit candidatePool;
        contours = {
          levels = densityPresets.${density};
        };
        inherit label;
        view = {
          tileConcurrency = 3;
          zoom = viewPresets.${view};
        };
      };
    };
  wallpapers = {
    dir = "${homeDirectory}/Pictures/Screensavers";
    dark = "${homeDirectory}/Pictures/Screensavers/wallpaper-dark.png";
    light = "${homeDirectory}/Pictures/Screensavers/wallpaper-light.png";
    current = "${homeDirectory}/Pictures/Screensavers/wallpaper.png";
    staticDark = ./wallpapers/topography-dark.png;
    staticLight = ./wallpapers/topography-light.png;
    generation = wallpaperGeneration;
  };
  paths = {
    stateDir = "${stateHome}/theme";
    stateFile = "${stateHome}/theme/current";
    fzfDir = "${configHome}/fzf/themes";
    fzfCurrentFile = "${configHome}/fzf/themes/theme";
    ghosttyDir = "${configHome}/ghostty/themes";
    ghosttyCurrentFile = "${configHome}/ghostty/themes/cozybox-current";
    lazygitDir = "${configHome}/lazygit";
    lazygitCurrentFile = "${configHome}/lazygit/config.yml";
    gitDir = "${configHome}/git";
    gitThemeCurrentFile = "${configHome}/git/theme.inc";
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
        showBottomLine: false
        showListFooter: false
        showPanelJumps: false
        showCommandLog: false
        showRandomTip: false
        splitDiff: auto
        border: rounded
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

  renderGitThemeInclude = mode: ''
    [delta]
      features = cozybox-${mode}
  '';

  deltaTheme =
    mode:
    let
      c =
        if mode == "light" then
          {
            modeFlag = true;
            file = "#4261a5";
            hunk = "#8f3f71";
            minus = "#fff0ed";
            minusEmph = "#ffd7d1";
            plus = "#edf6ed";
            plusEmph = "#d8ead8";
            lineMinus = "#c5524a";
            linePlus = "#427b58";
            zero = "#3c3836";
          }
        else
          {
            modeFlag = true;
            file = sharedPalette.blue;
            hunk = sharedPalette.purple;
            minus = "#3c1f1e";
            minusEmph = "#72261d";
            plus = "#1d2c1d";
            plusEmph = "#2b4a2b";
            lineMinus = sharedPalette.red;
            linePlus = sharedPalette.green;
            zero = "#d4be98";
          };
      modeKey = if mode == "light" then "light" else "dark";
    in
    {
      "${modeKey}" = c.modeFlag;
      "syntax-theme" = "none";
      "hunk-header-style" = "omit";
      "file-style" = c.file;
      "hunk-header-decoration-style" = c.hunk;
      "minus-style" = ''normal "${c.minus}"'';
      "minus-emph-style" = ''normal "${c.minusEmph}"'';
      "plus-style" = ''normal "${c.plus}"'';
      "plus-emph-style" = ''normal "${c.plusEmph}"'';
      "zero-style" = c.zero;
      "line-numbers-minus-style" = c.lineMinus;
      "line-numbers-plus-style" = c.linePlus;
      "line-numbers-zero-style" = sharedPalette.gray;
    };

  batTheme = mode: if mode == "light" then "gruvbox-light" else "gruvbox-dark";

  ompTheme =
    mode:
    let
      # nonicons codepoints (matches nonicons.nvim glyphs used in neovim)
      nonicon = hex: builtins.fromJSON ''"\u${hex}"'';
      c =
        if mode == "light" then
          {
            accent = "#665c54";
            borderAccent = "#3c3836";
            bright = "#282828";
            border = "#928374";
            borderMuted = "#c3c7c9";
            selectedBg = "#c3c7c9";
            green = "#427b58";
            red = "#c5524a";
            yellow = "#b57614";
            yellowBright = "#d79921";
            aqua = "#076678";
            purpleTone = "#8f3f71";
            coral = "#af3a03";
            linkBlue = "#4261a5";
            muted = "#665c54";
            dim = sharedPalette.gray;
            # monotone ramp: faint -> bright (darker = stronger on light bg)
            monoFaint = "#a89984";
            mono = "#7c6f64";
            monoMid = "#665c54";
            monoHigh = "#504945";
            monoBright = "#3c3836";
          }
        else
          {
            accent = "#d4be98";
            borderAccent = "#d4be98";
            bright = "#ebdbb2";
            border = "#504945";
            borderMuted = "#3c3836";
            selectedBg = "#504945";
            inherit (sharedPalette)
              aqua
              green
              red
              yellow
              yellowBright
              ;
            purpleTone = sharedPalette.purple;
            coral = "#d97757";
            linkBlue = sharedPalette.blue;
            muted = sharedPalette.gray;
            dim = "#7c6f64";
            # monotone ramp: faint -> bright
            monoFaint = "#665c54";
            mono = sharedPalette.gray;
            monoMid = "#a89984";
            monoHigh = "#bdae93";
            monoBright = "#d4be98";
          };
    in
    {
      name = "cozybox-${mode}";
      colors = {
        inherit (c)
          accent
          border
          borderAccent
          borderMuted
          dim
          muted
          selectedBg
          ;
        success = c.green;
        error = c.red;
        warning = c.yellow;
        text = "";
        thinkingText = c.dim;

        userMessageBg = "";
        userMessageText = c.bright;
        customMessageBg = "";
        customMessageText = "";
        customMessageLabel = c.monoMid;
        toolPendingBg = "";
        toolSuccessBg = "";
        toolErrorBg = "";
        toolTitle = c.monoHigh;
        toolOutput = c.muted;

        mdHeading = c.bright;
        mdLink = c.linkBlue;
        mdLinkUrl = c.dim;
        mdCode = c.coral;
        mdCodeBlock = c.bright;
        mdCodeBlockBorder = c.borderMuted;
        mdQuote = c.muted;
        mdQuoteBorder = c.border;
        mdHr = c.borderMuted;
        mdListBullet = c.mono;

        toolDiffAdded = c.green;
        toolDiffRemoved = c.red;
        toolDiffContext = c.muted;

        syntaxComment = c.dim;
        syntaxKeyword = c.red;
        syntaxFunction = c.yellowBright;
        syntaxVariable = "";
        syntaxString = c.green;
        syntaxNumber = c.purpleTone;
        syntaxType = c.yellow;
        syntaxOperator = c.aqua;
        syntaxPunctuation = c.muted;

        # monotone brightness ramp instead of per-level hues
        thinkingOff = c.monoFaint;
        thinkingMinimal = c.dim;
        thinkingLow = c.mono;
        thinkingMedium = c.monoMid;
        thinkingHigh = c.monoHigh;
        thinkingXhigh = c.monoBright;
        bashMode = c.mono;
        pythonMode = c.mono;

        statusLineBg = "";
        statusLineSep = c.border;
        statusLineModel = c.bright;
        statusLinePath = c.muted;
        statusLineGitClean = c.mono;
        statusLineGitDirty = c.monoMid;
        statusLineContext = c.muted;
        statusLineSpend = c.dim;
        statusLineStaged = c.mono;
        statusLineDirty = c.monoMid;
        statusLineUntracked = c.dim;
        statusLineOutput = "";
        statusLineCost = c.dim;
        statusLineSubagents = c.monoMid;
      };
      symbols = {
        preset = "nerd";
        # plain single-color braille spinner (no shimmer, no fancy frames)
        spinnerFrames = [
          "⠋"
          "⠙"
          "⠹"
          "⠸"
          "⠼"
          "⠴"
          "⠦"
          "⠧"
          "⠇"
          "⠏"
        ];
        overrides = {
          "boxRound.topLeft" = "┌";
          "boxRound.topRight" = "┐";
          "boxRound.bottomLeft" = "└";
          "boxRound.bottomRight" = "┘";
          "boxRound.horizontal" = "─";
          "boxRound.vertical" = "│";
          "boxSharp.topLeft" = "┌";
          "boxSharp.topRight" = "┐";
          "boxSharp.bottomLeft" = "└";
          "boxSharp.bottomRight" = "┘";
          "boxSharp.horizontal" = "─";
          "boxSharp.vertical" = "│";
          "boxSharp.cross" = "┼";
          "boxSharp.teeDown" = "┬";
          "boxSharp.teeUp" = "┴";
          "boxSharp.teeRight" = "├";
          "boxSharp.teeLeft" = "┤";
          # No icon next to the model name (renders as FA reddit-alien: f281 is
          # outside the ghostty nonicons map U+f101-U+f25c).
          "icon.model" = "";
          "icon.folder" = nonicon "f14b"; # file-directory
          "icon.file" = nonicon "f146"; # file
          "icon.git" = nonicon "f157"; # git-branch
          "icon.branch" = nonicon "f157"; # git-branch
          "icon.context" = ""; # no glyph next to context % (f188 rendered as junk)
          "icon.tokens" = nonicon "f245"; # stack
          "icon.cost" = "$";
          "icon.auto" = ""; # f2b0 is outside the nonicons map; rendered as junk
          "icon.time" = nonicon "f125"; # clock
          "icon.worktree" = nonicon "f14d"; # file-submodule
          "icon.search" = nonicon "f1bd"; # search
          "format.bracketLeft" = "[";
          "format.bracketRight" = "]";
          "thinking.minimal" = "min";
          "thinking.low" = "low";
          "thinking.medium" = "med";
          "thinking.high" = "high";
          "thinking.xhigh" = "xhigh";
          # File-type icons in tool-call headers: blanked. The guessed nonicons
          # codepoints rendered as random glyphs (github/bitbucket/car...), and
          # deleting the overrides would fall back to nerd-preset codepoints that
          # the ghostty nonicons map (U+f101-U+f25c) intercepts just as randomly.
          "lang.archive" = "";
          "lang.binary" = "";
          "lang.c" = "";
          "lang.conf" = "";
          "lang.cpp" = "";
          "lang.csharp" = "";
          "lang.css" = "";
          "lang.csv" = "";
          "lang.default" = "";
          "lang.docker" = "";
          "lang.env" = "";
          "lang.go" = "";
          "lang.html" = "";
          "lang.image" = "";
          "lang.ini" = "";
          "lang.java" = "";
          "lang.javascript" = "";
          "lang.json" = "";
          "lang.kotlin" = "";
          "lang.log" = "";
          "lang.lua" = "";
          "lang.markdown" = "";
          "lang.pdf" = "";
          "lang.php" = "";
          "lang.python" = "";
          "lang.ruby" = "";
          "lang.rust" = "";
          "lang.shell" = "";
          "lang.sql" = "";
          "lang.swift" = "";
          "lang.text" = "";
          "lang.toml" = "";
          "lang.tsv" = "";
          "lang.typescript" = "";
          "lang.xml" = "";
          "lang.yaml" = "";
        };
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
    deltaTheme
    ompTheme
    paths
    renderFzf
    renderGitThemeInclude
    renderGhostty
    renderLazygit
    renderPurePrompt
    renderZshHighlights
    themes
    wallpapers
    ;
}
