{ username }:
{
  user = {
    "anthropic.env" = { };
    "antithesis.env" = { };
    "linear.env" = { };
    "forgejo-token".exposeToShell = false;
    "cloudflare-api-token".exposeToShell = false;
    "heroku-uva.json".exposeToShell = false;
  };

  hosts.spark = {
    "sharefs-password" = {
      owner = username;
      restartUnits = [ "sharefs.service" ];
    };

    "sharefs-signing-key" = {
      owner = username;
      restartUnits = [ "sharefs.service" ];
    };

    "draw-google-oauth.env" = {
      format = "dotenv";
      restartUnits = [ "draw.service" ];
    };

    "wayvnc.conf".owner = username;
    "user-password-hash".neededForUsers = true;

    "wifi.env".restartUnits = [ "NetworkManager-ensure-profiles.service" ];

    "cloudflared.json" = {
      mode = "0444";
      restartUnits = [ "cloudflared-tunnel-64bce32c-6613-459c-bb68-262d73e1b78f.service" ];
    };

    "vaultwarden.env" = {
      owner = "vaultwarden";
      restartUnits = [ "vaultwarden.service" ];
    };

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
    };

    "forgejo-mirror-github-token.env" = {
      owner = "git";
      restartUnits = [ "forgejo.service" ];
    };

    "forgejo-mirror-github-accounts.env".owner = "git";

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

    "hermes.env" = {
      format = "dotenv";
      restartUnits = [
        "hermes-agent.service"
        "hermes-backend.service"
      ];
    };
  };
}
