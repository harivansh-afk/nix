{
  config,
  lib,
  pkgs,
}:
let
  theme = import ../lib/theme.nix { inherit config; };

  tmuxConfigs = {
    dark = pkgs.writeText "tmux-theme-dark.conf" (theme.renderTmux "dark");
    light = pkgs.writeText "tmux-theme-light.conf" (theme.renderTmux "light");
  };

  wallpaperGenConfig = pkgs.writeText "wallpaper-gen-config.json" (
    builtins.toJSON theme.wallpapers.generation.resolved
  );

  wallpaperPython = pkgs.python3.withPackages (ps: [ ps.pillow ]);

  lazygitDarwinDir = "${config.home.homeDirectory}/Library/Application Support/lazygit";

  modeAssets = {
    dark = {
      fzf = "${theme.paths.fzfDir}/cozybox-dark";
      ghostty = "${theme.paths.ghosttyDir}/cozybox-dark";
      tmux = "${tmuxConfigs.dark}";
      lazygit = "${theme.paths.lazygitDir}/config-dark.yml";
      darwinLazygit = "${lazygitDarwinDir}/config-dark.yml";
      wallpaper = theme.wallpapers.dark;
      appleDarkMode = "true";
    };
    light = {
      fzf = "${theme.paths.fzfDir}/cozybox-light";
      ghostty = "${theme.paths.ghosttyDir}/cozybox-light";
      tmux = "${tmuxConfigs.light}";
      lazygit = "${theme.paths.lazygitDir}/config-light.yml";
      darwinLazygit = "${lazygitDarwinDir}/config-light.yml";
      wallpaper = theme.wallpapers.light;
      appleDarkMode = "false";
    };
  };

  themeAssetsText = ''
    theme_normalize_mode() {
      case "$1" in
        dark|light) printf '%s\n' "$1" ;;
        *) printf '%s\n' '${theme.defaultMode}' ;;
      esac
    }

    theme_load_mode_assets() {
      local mode
      mode="$(theme_normalize_mode "$1")"

      case "$mode" in
        light)
          THEME_MODE='light'
          THEME_FZF_TARGET='${modeAssets.light.fzf}'
          THEME_GHOSTTY_TARGET='${modeAssets.light.ghostty}'
          THEME_TMUX_TARGET='${modeAssets.light.tmux}'
          THEME_LAZYGIT_TARGET='${modeAssets.light.lazygit}'
          THEME_DARWIN_LAZYGIT_TARGET='${modeAssets.light.darwinLazygit}'
          THEME_WALLPAPER='${modeAssets.light.wallpaper}'
          THEME_APPLE_DARK_MODE=${modeAssets.light.appleDarkMode}
          ;;
        *)
          THEME_MODE='dark'
          THEME_FZF_TARGET='${modeAssets.dark.fzf}'
          THEME_GHOSTTY_TARGET='${modeAssets.dark.ghostty}'
          THEME_TMUX_TARGET='${modeAssets.dark.tmux}'
          THEME_LAZYGIT_TARGET='${modeAssets.dark.lazygit}'
          THEME_DARWIN_LAZYGIT_TARGET='${modeAssets.dark.darwinLazygit}'
          THEME_WALLPAPER='${modeAssets.dark.wallpaper}'
          THEME_APPLE_DARK_MODE=${modeAssets.dark.appleDarkMode}
          ;;
      esac
    }
  '';

  mkScript =
    {
      file,
      name,
      runtimeInputs ? [ ],
      replacements ? { },
    }:
    pkgs.writeShellApplication {
      inherit name runtimeInputs;
      text = lib.replaceStrings (builtins.attrNames replacements) (builtins.attrValues replacements) (
        builtins.readFile file
      );
    };

  commonPackages = {
    ga = mkScript {
      name = "ga";
      file = ./bin/ga.sh;
      runtimeInputs = with pkgs; [ git ];
    };

    ghpr = mkScript {
      name = "ghpr";
      file = ./bin/ghpr.sh;
      runtimeInputs = with pkgs; [
        gh
        git
        gnugrep
        gnused
        coreutils
      ];
    };

    iosrun = mkScript {
      name = "iosrun";
      file = ./bin/iosrun.sh;
      runtimeInputs = with pkgs; [
        findutils
        gnugrep
        coreutils
      ];
    };

    wallpaper-gen = mkScript {
      name = "wallpaper-gen";
      file = ./bin/wallpaper-gen.sh;
      runtimeInputs = [ wallpaperPython ];
      replacements = {
        "@WALLPAPER_GEN_PY@" = "${./lib/wallpaper-gen.py}";
        "@WALLPAPER_GEN_CONFIG@" = "${wallpaperGenConfig}";
      };
    };

    theme = mkScript {
      name = "theme";
      file = ./bin/theme.sh;
      runtimeInputs = with pkgs; [
        coreutils
        findutils
        neovim
        tmux
      ];
      replacements = {
        "@DEFAULT_MODE@" = theme.defaultMode;
        "@STATE_DIR@" = theme.paths.stateDir;
        "@STATE_FILE@" = theme.paths.stateFile;
        "@FZF_DIR@" = theme.paths.fzfDir;
        "@FZF_CURRENT_FILE@" = theme.paths.fzfCurrentFile;
        "@GHOSTTY_DIR@" = theme.paths.ghosttyDir;
        "@GHOSTTY_CURRENT_FILE@" = theme.paths.ghosttyCurrentFile;
        "@TMUX_DIR@" = theme.paths.tmuxDir;
        "@TMUX_CURRENT_FILE@" = theme.paths.tmuxCurrentFile;
        "@TMUX_CONFIG@" = "${config.xdg.configHome}/tmux/tmux.conf";
        "@LAZYGIT_DIR@" = theme.paths.lazygitDir;
        "@LAZYGIT_CURRENT_FILE@" = theme.paths.lazygitCurrentFile;
        "@LAZYGIT_DARWIN_DIR@" = lazygitDarwinDir;
        "@LAZYGIT_DARWIN_FILE@" = "${lazygitDarwinDir}/config.yml";
        "@WALLPAPER_DIR@" = theme.wallpapers.dir;
        "@WALLPAPER_CURRENT_FILE@" = theme.wallpapers.current;
        "@WALLPAPER_STATIC_DARK@" = "${theme.wallpapers.staticDark}";
        "@WALLPAPER_STATIC_LIGHT@" = "${theme.wallpapers.staticLight}";
        "@THEME_ASSETS_TEXT@" = themeAssetsText;
      };
    };
  };

  darwinPackages = { };

  linuxPackages = {
    wt = mkScript {
      name = "wt";
      file = ./bin/wt.sh;
      runtimeInputs = with pkgs; [
        coreutils
        git
        gnused
      ];
    };
  };
in
{
  inherit
    commonPackages
    darwinPackages
    linuxPackages
    theme
    themeAssetsText
    tmuxConfigs
    ;
}
