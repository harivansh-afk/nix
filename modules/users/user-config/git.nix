# git: credential helpers and delta themes need nix rendering.
#
# The credential helpers read forgejo tokens from /run/secrets at runtime;
# the delta themes are rendered from the cozybox palette.
{
  lib,
  pkgs,
  theme,
  ...
}:
let
  forgejoCredentialHelper = pkgs.writeShellScript "git-credential-forgejo" ''
    if [ "$1" = "get" ] && [ -r /run/secrets/forgejo-token.env ]; then
      echo "username=harivansh-afk"
      echo "password=$(cat /run/secrets/forgejo-token.env)"
    fi
  '';

  ixForgejoCredentialHelper = pkgs.writeShellScript "git-credential-ix-forgejo" ''
    if [ "$1" = "get" ] && [ -r /run/secrets/forgejo-ix.env ]; then
      set -a
      . /run/secrets/forgejo-ix.env
      echo "username=harivansh-afk"
      echo "password=$FORGEJO_IX_TOKEN"
    fi
  '';

  renderGitSection =
    sectionName: attrs:
    let
      renderValue = v: if builtins.isBool v then (if v then "true" else "false") else toString v;
      lines = lib.mapAttrsToList (k: v: "	${k} = ${renderValue v}") attrs;
    in
    "[${sectionName}]\n" + lib.concatStringsSep "\n" lines;
in
{
  gitCredentialsInc = pkgs.writeText "git-credentials.inc" ''
    [credential "https://git.harivan.sh"]
    	helper = !${forgejoCredentialHelper}
    	username = harivansh-afk

    [credential "https://git.ix.dev"]
    	helper = !${ixForgejoCredentialHelper}
    	username = harivansh-afk
  '';

  gitDeltaThemesInc = pkgs.writeText "git-delta-themes.inc" ''
    ${renderGitSection ''delta "cozybox-dark"'' (theme.deltaTheme "dark")}

    ${renderGitSection ''delta "cozybox-light"'' (theme.deltaTheme "light")}
  '';
}
