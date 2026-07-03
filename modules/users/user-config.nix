# Per-user config builder (no home-manager). Returns { script, packages }:
# `packages` go into the user's profile, `script` is run as the user by the
# darwin/nixos activation adapters to materialise dotfiles and symlinks.
#
# The concerns are split across user-config/:
#   env.nix         session environment (XDG dirs, tool homes)
#   shell.nix       zsh shims + prompt/highlight themes
#   git.nix         credential helpers + delta themes
#   agents.nix      claude settings + codex seed metadata
#   apps.nix        btop/fzf/ghostty/lazygit/nvim aliases/helium
#   tea.nix         tea login fragment
#   packages.nix    the package set
#   activation.nix  the bash activation script that wires it all together
{
  lib,
  pkgs,
  user,
  dotsRoot,
  hostname,
  isDarwin,
  extraPackages ? [ ],
}:
let
  inherit (user) name homeDirectory;
  configHome = "${homeDirectory}/.config";
  binHome = "${homeDirectory}/.local/bin";
  dataHome = "${homeDirectory}/.local/share";
  stateHome = "${homeDirectory}/.local/state";
  cacheHome = "${homeDirectory}/.cache";

  theme = import ../../lib/theme.nix { inherit homeDirectory; };
  customScripts = import ../../scripts { inherit homeDirectory lib pkgs; };
  coreutilsBin = "${pkgs.coreutils}/bin";

  base = {
    inherit
      lib
      pkgs
      name
      homeDirectory
      configHome
      binHome
      dataHome
      stateHome
      cacheHome
      dotsRoot
      hostname
      isDarwin
      theme
      customScripts
      coreutilsBin
      ;
  };

  env = import ./user-config/env.nix base;
  shell = import ./user-config/shell.nix (base // { inherit (env) sessionVars; });
  git = import ./user-config/git.nix base;
  agents = import ./user-config/agents.nix base;
  apps = import ./user-config/apps.nix base;
  tea = import ./user-config/tea.nix base;

  packages = import ./user-config/packages.nix (
    base
    // {
      inherit extraPackages;
      inherit (apps) nvimAliases;
    }
  );

  script = import ./user-config/activation.nix (
    base
    // {
      inherit (env) environmentD;
      inherit (shell) zshenvShim zshrcShim zshThemes;
      inherit (git) gitCredentialsInc gitDeltaThemesInc;
      inherit (agents)
        claudeSettings
        codexConfigSource
        readXattr
        writeXattr
        ompThemes
        ompConfigSource
        ompReadXattr
        ompWriteXattr
        ;
      inherit (apps)
        btopConf
        fzfThemes
        ghosttyThemes
        lazygitConfigs
        heliumExtJson
        heliumExtensions
        ;
      inherit (tea) teaLoginYaml;
    }
  );
in
{
  inherit script packages;
}
