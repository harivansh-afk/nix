# zsh shims and prompt/highlight themes.
#
# The shims live in the store and defer to the live dotfiles, so editing
# dots/zsh applies without a rebuild. Store paths are sourced first, then
# the live dots file.
{
  lib,
  pkgs,
  name,
  dotsRoot,
  theme,
  sessionVars,
  ...
}:
let
  userSecretRegistry = (import ../../../secrets/registry.nix { username = name; }).user;
  shellSecretRegistry = lib.filterAttrs (_: cfg: cfg.exposeToShell or true) userSecretRegistry;
  loadUserSecrets = lib.concatMapStringsSep "\n" (secretName: ''
    if [[ -r /run/secrets/${secretName} ]]; then
      set -a; source /run/secrets/${secretName}; set +a
    fi
  '') (builtins.attrNames shellSecretRegistry);

  mkZshTheme =
    mode:
    pkgs.writeText "zsh-theme-${mode}.zsh" ''
      ${theme.renderPurePrompt mode}
      typeset -gA ZSH_HIGHLIGHT_STYLES
      ${theme.renderZshHighlights mode}
    '';
in
{
  zshenvShim = pkgs.writeText "zshenv-shim" ''
    source ${sessionVars}
    source "${dotsRoot}/zsh/zshenv"
  '';

  zshrcShim = pkgs.writeText "zshrc-shim" ''
    source ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh
    fpath+=("${pkgs.pure-prompt}/share/zsh/site-functions")

    ${loadUserSecrets}

    export DOTS_ZSH_DIR="${dotsRoot}/zsh"
    source "${dotsRoot}/zsh/zshrc"

    # syntax highlighting wants to be sourced last
    source ${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
  '';

  zshThemes = {
    dark = mkZshTheme "dark";
    light = mkZshTheme "light";
  };
}
