# Every sops secret in the flake. modules/security/sops.nix declares these;
# the file for `user.<name>` is secrets/user/<name>, for `hosts.<host>.<name>`
# it is secrets/hosts/<host>/<name>, and each lands at /run/secrets/<name>.
#
# user secrets decrypt on every host the admin key reaches, default to
# owner = username and mode 0400, and are sourced into interactive zsh unless
# `exposeToShell = false` (raw tokens, anything that is not KEY=value).
# host secrets decrypt on that host only; the entry is passed to sops.secrets
# as is (owner, group, mode, restartUnits, neededForUsers).
{ username }:
{
  user = {
    "anthropic.env" = { };
    "antithesis.env" = { };
    "linear.env" = { };
    "graphite.env" = { };
    "mgrep.env" = { };
    "gws.env" = { };
    "mxbai.env" = { };
    "forgejo-ix.env".format = "dotenv";
    "forgejo-token".exposeToShell = false;
    "cloudflare-api-token".exposeToShell = false;
  };

  hosts.spark = {
    "user-password-hash".neededForUsers = true;

    "hermes-dashboard.env" = {
      format = "dotenv";
      owner = username;
      restartUnits = [ "hermes-backend.service" ];
    };

    # gws OAuth token, read by the gmail and calendar KB connectors (run as the user).
    "gws-credentials.json" = {
      owner = username;
    };

    "wifi.env".restartUnits = [ "NetworkManager-ensure-profiles.service" ];

    "tailscale-ix-authkey" = {
      owner = "root";
      restartUnits = [ "tailscaled-autoconnect.service" ];
    };

    "cloudflared.json" = {
      mode = "0444";
      restartUnits = [ "cloudflared-tunnel-64bce32c-6613-459c-bb68-262d73e1b78f.service" ];
    };

    "vaultwarden.env" = {
      owner = "vaultwarden";
      restartUnits = [ "vaultwarden.service" ];
    };

    # Spotify client-credentials pair for the mixbridge yt-dlp API.
    "mixbridge.env" = {
      format = "dotenv";
      restartUnits = [ "mixbridge-api.service" ];
    };

    "forgejo-smtp-password" = {
      owner = "git";
      restartUnits = [ "forgejo.service" ];
    };

    "forgejo-mirror.env" = {
      owner = "git";
      restartUnits = [ "forgejo.service" ];
    };

    "forgejo-mirror-github-token.env" = {
      owner = "git";
      restartUnits = [ "forgejo.service" ];
    };

    "forgejo-google-oauth.env" = {
      owner = "git";
      restartUnits = [ "forgejo.service" ];
    };

    "forgejo-github-oauth.env" = {
      owner = "git";
      restartUnits = [ "forgejo.service" ];
    };

    "forgejo-runner-token" = {
      owner = "gitea-runner";
      restartUnits = [ "gitea-runner-spark.service" ];
    };
  };
}
