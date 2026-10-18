{
  pkgs,
  neovim,
  theme,
  isDarwin,
  ...
}:
{
  nvimAliases = pkgs.runCommand "nvim-command-aliases" { } ''
    mkdir -p "$out/bin"
    ln -s ${neovim}/bin/nvim "$out/bin/vi"
    ln -s ${neovim}/bin/nvim "$out/bin/vim"
    ln -s ${neovim}/bin/nvim "$out/bin/view"
    ln -s ${neovim}/bin/nvim "$out/bin/vimdiff"
  '';

  fzfThemes = {
    dark = pkgs.writeText "fzf-cozybox-dark" (theme.renderFzf "dark");
    light = pkgs.writeText "fzf-cozybox-light" (theme.renderFzf "light");
  };

  ghosttyTerminfo = (if isDarwin then pkgs.ghostty-bin else pkgs.ghostty).terminfo;

  ghosttyThemes = {
    dark = pkgs.writeText "ghostty-cozybox-dark" (theme.renderGhostty "dark");
    light = pkgs.writeText "ghostty-cozybox-light" (theme.renderGhostty "light");
  };

  rexDefaults = {
    darkThemeID = (theme.renderRex "dark").id;
    lightThemeID = (theme.renderRex "light").id;
    appearance = "system";
    interfaceStyle = "system";
    paneDensity = "compact";
    fadesInactivePanes = false;
    usesPaneGlass = false;
    showsPaneHeaders = false;
    balancesSplitsOnCreation = true;
    sidebarPosition = "left";
    tabStyle = "horizontal";
    tabsFillAvailableSpace = false;
    tabIconTintMode = "off";
    showsProgramStatusInTabs = true;
    terminalFontName = "Berkeley Mono Nonicons";
    terminalFontPointSize = 18.0;
    terminalFontSmoothing = false;
    terminalOptionKeyBehavior = "actsAsAlt";
    terminalPaddingColor = "extend";
    terminalCopyOnSelect = true;
  };

  rexThemes = pkgs.writeText "rex-themes.json" (
    builtins.toJSON [
      (theme.renderRex "dark")
      (theme.renderRex "light")
    ]
  );

  rexFont =
    let
      nonicons = "${pkgs.callPackage ../../../pkgs/nonicons.nix { }}/share/fonts/truetype/nonicons.ttf";
      python = pkgs.python3.withPackages (ps: [ ps.fonttools ]);
      merge = ../../../pkgs/scripts/lib/rex-font.py;
    in
    pkgs.writeShellScript "rex-font" ''
      set -eu
      fonts="$HOME/Library/Fonts"
      stamp="$HOME/.local/state/rex/font.stamp"
      sources=""
      for style in Regular Bold; do
        [ -f "$fonts/BerkeleyMono-$style.otf" ] && sources="$sources $fonts/BerkeleyMono-$style.otf"
      done
      [ -n "$sources" ] || exit 0
      want="$(cat $sources ${nonicons} ${merge} | sha256sum | cut -d' ' -f1)"
      [ "$(cat "$stamp" 2>/dev/null)" = "$want" ] && exit 0
      for src in $sources; do
        style="''${src##*-}"
        style="''${style%.otf}"
        ${python}/bin/python3 -I ${merge} "$src" ${nonicons} \
          "$fonts/BerkeleyMonoNonicons-$style.otf" "Berkeley Mono Nonicons" "BerkeleyMonoNonicons-$style"
      done
      mkdir -p "''${stamp%/*}"
      printf '%s\n' "$want" > "$stamp"
    '';

  sketchybarThemes = {
    dark = pkgs.writeText "sketchybar-cozybox-dark.sh" (theme.renderSketchybar "dark");
    light = pkgs.writeText "sketchybar-cozybox-light.sh" (theme.renderSketchybar "light");
  };

  heliumExtensions = [
    "ddkjiahejlhfcafbddmgiahcphecmpfh"
    "fcoeoabgfenejglbffodgkkbkcdhcgfn"
    "nngceckbapebfimnlniiiahkandclblb"
  ];

  heliumExtJson = pkgs.writeText "helium-ext.json" (
    builtins.toJSON { external_update_url = "https://clients2.google.com/service/update2/crx"; }
  );
}
