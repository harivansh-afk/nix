{
  lib,
  pkgs,
  hostname,
  forgeLogins,
  ...
}:
let
  forgejoCredentialHelper = pkgs.writeShellScript "git-credential-forgejo" ''
    if [ "$1" = "get" ] && [ -r /run/secrets/forgejo-token ]; then
      echo "username=${forgeLogins.harivan}"
      echo "password=$(cat /run/secrets/forgejo-token)"
    fi
  '';

in
{
  gitCredentialsInc = pkgs.writeText "git-credentials.inc" (
    ''
      [credential "https://git.harivan.sh"]
      	helper = !${forgejoCredentialHelper}
      	username = ${forgeLogins.harivan}
    ''

    + lib.optionalString (hostname == "spark") ''

      [url "git@localhost:"]
      	insteadOf = https://git.harivan.sh/
      	insteadOf = git@git.harivan.sh:
    ''
  );

}
