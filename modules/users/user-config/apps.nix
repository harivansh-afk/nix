# Assorted app configs rendered from the palette, plus the nvim command
# aliases and the darwin-only helium managed-extension manifest.
{
  pkgs,
  neovim,
  theme,
  isDarwin,
  ...
}:
let
  lazygitBase = builtins.readFile ../../../dots/lazygit/config.yml;
in
{
  nvimAliases = pkgs.runCommand "nvim-command-aliases" { } ''
    mkdir -p "$out/bin"
    ln -s ${neovim}/bin/nvim "$out/bin/vi"
    ln -s ${neovim}/bin/nvim "$out/bin/vim"
    ln -s ${neovim}/bin/nvim "$out/bin/view"
    ln -s ${neovim}/bin/nvim "$out/bin/vimdiff"
  '';

  # @HOSTNAME@ is substituted at activation time with the node's runtime
  # hostname: the same closure gets deployed to nodes this flake did not
  # build for, so baking the eval-time hostname in labels every node with
  # the build host's name.
  btopConf = pkgs.writeText "btop.conf" ''
    color_theme = "cozybox-current"
    custom_cpu_name = "@HOSTNAME@"
    rounded_corners = False
    theme_background = False
    vim_keys = True
  '';

  btopThemes = {
    dark = pkgs.writeText "btop-cozybox-dark.theme" (theme.renderBtop "dark");
    light = pkgs.writeText "btop-cozybox-light.theme" (theme.renderBtop "light");
  };

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

  lazygitConfigs = {
    dark = pkgs.writeText "lazygit-config-dark.yml" (lazygitBase + theme.renderLazygit "dark");
    light = pkgs.writeText "lazygit-config-light.yml" (lazygitBase + theme.renderLazygit "light");
  };

  # darwin: helium managed extensions
  heliumExtensions = [
    "ddkjiahejlhfcafbddmgiahcphecmpfh" # uBlock Origin Lite
    "fcoeoabgfenejglbffodgkkbkcdhcgfn" # Claude for Chrome
    "nngceckbapebfimnlniiiahkandclblb" # Bitwarden
  ];

  heliumExtJson = pkgs.writeText "helium-ext.json" (
    builtins.toJSON { external_update_url = "https://clients2.google.com/service/update2/crx"; }
  );
}
