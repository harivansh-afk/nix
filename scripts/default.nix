{
  config,
  lib,
  pkgs,
}: let
  theme = import ../lib/theme.nix {inherit config;};

  tmuxConfigs = {
    dark = pkgs.writeText "tmux-theme-dark.conf" (theme.renderTmux "dark");
    light = pkgs.writeText "tmux-theme-light.conf" (theme.renderTmux "light");
  };

  mkScript = {
    file,
    name,
    runtimeInputs ? [],
    replacements ? {},
  }:
    pkgs.writeShellApplication {
      inherit name runtimeInputs;
      text =
        lib.replaceStrings
        (builtins.attrNames replacements)
        (builtins.attrValues replacements)
        (builtins.readFile file);
    };

  packages = {
    ga = mkScript {
      name = "ga";
      file = ./ga.sh;
      runtimeInputs = with pkgs; [git];
    };

    ghpr = mkScript {
      name = "ghpr";
      file = ./ghpr.sh;
      runtimeInputs = with pkgs; [gh git gnugrep gnused coreutils];
    };

    gpr = mkScript {
      name = "gpr";
      file = ./gpr.sh;
      runtimeInputs = with pkgs; [gh fzf gnugrep coreutils];
    };

    iosrun = mkScript {
      name = "iosrun";
      file = ./iosrun.sh;
      runtimeInputs = with pkgs; [findutils gnugrep coreutils];
    };

    mdview = mkScript {
      name = "mdview";
      file = ./mdview.sh;
    };

    ni = mkScript {
      name = "ni";
      file = ./ni.sh;
      runtimeInputs = with pkgs; [nix];
    };

    theme = mkScript {
      name = "theme";
      file = ./theme.sh;
      runtimeInputs = with pkgs; [coreutils findutils neovim tmux];
      replacements = {
        "@DEFAULT_MODE@" = theme.defaultMode;
        "@STATE_DIR@" = theme.paths.stateDir;
        "@STATE_FILE@" = theme.paths.stateFile;
        "@GHOSTTY_DIR@" = theme.paths.ghosttyDir;
        "@GHOSTTY_CURRENT_FILE@" = theme.paths.ghosttyCurrentFile;
        "@GHOSTTY_DARK_FILE@" = "${theme.paths.ghosttyDir}/cozybox-dark";
        "@GHOSTTY_LIGHT_FILE@" = "${theme.paths.ghosttyDir}/cozybox-light";
        "@TMUX_DIR@" = theme.paths.tmuxDir;
        "@TMUX_CURRENT_FILE@" = theme.paths.tmuxCurrentFile;
        "@TMUX_DARK_FILE@" = "${tmuxConfigs.dark}";
        "@TMUX_LIGHT_FILE@" = "${tmuxConfigs.light}";
        "@TMUX_CONFIG@" = "${config.xdg.configHome}/tmux/tmux.conf";
      };
    };

    wtc = mkScript {
      name = "wtc";
      file = ./wtc.sh;
    };
  };
in {
  inherit packages theme tmuxConfigs;
}
