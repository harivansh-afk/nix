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
    "claude-proxy-api-keys".owner = username;
    "user-password-hash".neededForUsers = true;

    "hermes-dashboard.env" = {
      format = "dotenv";
      owner = username;
      restartUnits = [ "hermes-backend.service" ];
    };

    "hermes-voice.env" = {
      format = "dotenv";
      owner = "root";
      restartUnits = [ "hermes-backend.service" ];
    };

    "hermes-relay.env" = {
      format = "dotenv";
      owner = username;
      restartUnits = [ "hermes-agent.service" ];
    };

    "hermes-telegram.env" = {
      owner = username;
      restartUnits = [ "hermes-agent.service" ];
    };

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
