# Assorted app configs rendered from the palette, plus the nvim command
# aliases and the darwin-only helium managed-extension manifest.
{
  pkgs,
  theme,
  hostname,
  ...
}:
let
  lazygitBase = builtins.readFile ../../../dots/lazygit/config.yml;
in
{
  nvimAliases = pkgs.runCommand "nvim-command-aliases" { } ''
    mkdir -p "$out/bin"
    ln -s ${pkgs.neovim}/bin/nvim "$out/bin/vi"
    ln -s ${pkgs.neovim}/bin/nvim "$out/bin/vim"
    ln -s ${pkgs.neovim}/bin/nvim "$out/bin/view"
    ln -s ${pkgs.neovim}/bin/nvim "$out/bin/vimdiff"
  '';

  btopConf = pkgs.writeText "btop.conf" ''
    color_theme = "ayu"
    custom_cpu_name = "${hostname}"
    rounded_corners = False
    theme_background = False
    vim_keys = True
  '';

  fzfThemes = {
    dark = pkgs.writeText "fzf-cozybox-dark" (theme.renderFzf "dark");
    light = pkgs.writeText "fzf-cozybox-light" (theme.renderFzf "light");
  };

  ghosttyThemes = {
    dark = pkgs.writeText "ghostty-cozybox-dark" (theme.renderGhostty "dark");
    light = pkgs.writeText "ghostty-cozybox-light" (theme.renderGhostty "light");
  };

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
