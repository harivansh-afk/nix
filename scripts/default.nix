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
      wallpaper = theme.wallpapers.dark;
      appleDarkMode = "true";
    };
    light = {
      fzf = "${theme.paths.fzfDir}/cozybox-light";
      ghostty = "${theme.paths.ghosttyDir}/cozybox-light";
      lazygit = "${theme.paths.lazygitDir}/config-light.yml";
      gitTheme = "${gitThemeIncludes.light}";
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
          THEME_LAZYGIT_TARGET='${modeAssets.light.lazygit}'
          THEME_GIT_THEME_TARGET='${modeAssets.light.gitTheme}'
          THEME_DARWIN_LAZYGIT_TARGET='${modeAssets.light.darwinLazygit}'
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

  remotes = import ../lib/remotes.nix;

  remotePackages = lib.mapAttrs (
    name: remote:
    mkScript {
      inherit name;
      file = ./bin/remote.sh;
      runtimeInputs = [ pkgs.mosh ];
      replacements = {
        "@NAME@" = name;
        "@HOST@" = remote.host;
      };
    }
  ) remotes;

  commonPackages = {
    mux = mkScript {
      name = "mux";
      file = ./bin/mux.sh;
      runtimeInputs =
        with pkgs;
        [
          coreutils
          fzf
          gawk
          git
          gnugrep
          gnused
        ]
        ++ lib.optionals stdenv.isLinux [ util-linux ];
    };

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
        "@WALLPAPER_DIR@" = theme.wallpapers.dir;
        "@WALLPAPER_CURRENT_FILE@" = theme.wallpapers.current;
        "@WALLPAPER_STATIC_DARK@" = "${theme.wallpapers.staticDark}";
        "@WALLPAPER_STATIC_LIGHT@" = "${theme.wallpapers.staticLight}";
        "@THEME_ASSETS_TEXT@" = themeAssetsText;
      };
    };
  }
  // remotePackages;

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
