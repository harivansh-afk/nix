# git: credential helpers need nix rendering; they read forgejo tokens from
# /run/secrets at runtime.
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
    # spark hosts git.harivan.sh itself: rewrite git ops to loopback SSH so
    # they skip the WAN round-trip through the Cloudflare tunnel (latency +
    # 100 MB request-body cap on pushes). forgejo serv still runs all hooks,
    # so Actions and webhooks fire as usual.
    + lib.optionalString (hostname == "spark") ''

      [url "git@localhost:"]
      	insteadOf = https://git.harivan.sh/
      	insteadOf = git@git.harivan.sh:
    ''
  );

}
