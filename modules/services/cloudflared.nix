{
  config,
  mkSparkSecret,
  ...
}:
let
  tunnelId = "64bce32c-6613-459c-bb68-262d73e1b78f";
in
{
  sops.secrets."cloudflared-credentials" = mkSparkSecret "cloudflared.json" {
    mode = "0444";
    restartUnits = [ "cloudflared-tunnel-${tunnelId}.service" ];
  };

  services.cloudflared = {
    enable = true;
    tunnels.${tunnelId} = {
      credentialsFile = config.sops.secrets."cloudflared-credentials".path;
      default = "http://127.0.0.1:80";
      ingress = { };
    };
  };
}
