{
  homeDirectory,
  lib,
  pkgs,
}:
let
  theme = import ../lib/theme.nix { inherit homeDirectory; };

  gitThemeIncludes = {
    dark = pkgs.writeText "git-theme-dark.inc" (theme.renderGitThemeInclude "dark");
    light = pkgs.writeText "git-theme-light.inc" (theme.renderGitThemeInclude "light");
  };

  wallpaperGenConfig = pkgs.writeText "wallpaper-gen-config.json" (
    builtins.toJSON theme.wallpapers.generation.resolved
  );

  wallpaperPython = pkgs.python3.withPackages (ps: [ ps.pillow ]);

  lazygitDarwinDir = "${homeDirectory}/Library/Application Support/lazygit";

  modeAssets = {
    dark = {
      fzf = "${theme.paths.fzfDir}/cozybox-dark";
      ghostty = "${theme.paths.ghosttyDir}/cozybox-dark";
      lazygit = "${theme.paths.lazygitDir}/config-dark.yml";
      gitTheme = "${gitThemeIncludes.dark}";
      darwinLazygit = "${lazygitDarwinDir}/config-dark.yml";
      sketchybar = "${theme.paths.sketchybarDir}/cozybox-dark.sh";
      wallpaper = theme.wallpapers.dark;
      appleDarkMode = "true";
    };
    light = {
      fzf = "${theme.paths.fzfDir}/cozybox-light";
      ghostty = "${theme.paths.ghosttyDir}/cozybox-light";
      lazygit = "${theme.paths.lazygitDir}/config-light.yml";
      gitTheme = "${gitThemeIncludes.light}";
      darwinLazygit = "${lazygitDarwinDir}/config-light.yml";
      sketchybar = "${theme.paths.sketchybarDir}/cozybox-light.sh";
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
          THEME_LAZYGIT_TARGET='${modeAssets.light.lazygit}'
          THEME_GIT_THEME_TARGET='${modeAssets.light.gitTheme}'
          THEME_DARWIN_LAZYGIT_TARGET='${modeAssets.light.darwinLazygit}'
          THEME_SKETCHYBAR_TARGET='${modeAssets.light.sketchybar}'
          THEME_WALLPAPER='${modeAssets.light.wallpaper}'
          THEME_APPLE_DARK_MODE=${modeAssets.light.appleDarkMode}
          ;;
        *)
          THEME_MODE='dark'
          THEME_FZF_TARGET='${modeAssets.dark.fzf}'
          THEME_GHOSTTY_TARGET='${modeAssets.dark.ghostty}'
          THEME_LAZYGIT_TARGET='${modeAssets.dark.lazygit}'
          THEME_GIT_THEME_TARGET='${modeAssets.dark.gitTheme}'
          THEME_DARWIN_LAZYGIT_TARGET='${modeAssets.dark.darwinLazygit}'
          THEME_SKETCHYBAR_TARGET='${modeAssets.dark.sketchybar}'
          THEME_WALLPAPER='${modeAssets.dark.wallpaper}'
          THEME_APPLE_DARK_MODE=${modeAssets.dark.appleDarkMode}
          ;;
      esac
    }
  '';

  portable = import ./portable.nix { inherit lib pkgs; };

  inherit (portable) mkScript;

  commonPackages = portable.packages // {
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
      ];
      replacements = {
        "@DEFAULT_MODE@" = theme.defaultMode;
        "@STATE_DIR@" = theme.paths.stateDir;
        "@STATE_FILE@" = theme.paths.stateFile;
        "@FZF_DIR@" = theme.paths.fzfDir;
        "@FZF_CURRENT_FILE@" = theme.paths.fzfCurrentFile;
        "@GHOSTTY_DIR@" = theme.paths.ghosttyDir;
        "@GHOSTTY_CURRENT_FILE@" = theme.paths.ghosttyCurrentFile;
        "@LAZYGIT_DIR@" = theme.paths.lazygitDir;
        "@LAZYGIT_CURRENT_FILE@" = theme.paths.lazygitCurrentFile;
        "@GIT_THEME_DIR@" = theme.paths.gitDir;
        "@GIT_THEME_CURRENT_FILE@" = theme.paths.gitThemeCurrentFile;
        "@LAZYGIT_DARWIN_DIR@" = lazygitDarwinDir;
        "@LAZYGIT_DARWIN_FILE@" = "${lazygitDarwinDir}/config.yml";
        "@SKETCHYBAR_DIR@" = theme.paths.sketchybarDir;
        "@SKETCHYBAR_CURRENT_FILE@" = theme.paths.sketchybarCurrentFile;
        "@WALLPAPER_DIR@" = theme.wallpapers.dir;
        "@WALLPAPER_CURRENT_FILE@" = theme.wallpapers.current;
        "@WALLPAPER_STATIC_DARK@" = "${theme.wallpapers.staticDark}";
        "@WALLPAPER_STATIC_LIGHT@" = "${theme.wallpapers.staticLight}";
        "@THEME_ASSETS_TEXT@" = themeAssetsText;
      };
    };
  };

  darwinPackages = { };

  linuxPackages = { };
in
{
  inherit
    commonPackages
    darwinPackages
    linuxPackages
    theme
    themeAssetsText
    ;
}
