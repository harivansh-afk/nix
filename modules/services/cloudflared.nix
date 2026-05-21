{
  config,
  ...
}:
let
  tunnelId = "64bce32c-6613-459c-bb68-262d73e1b78f";
in
{
  services.cloudflared = {
    enable = true;
    tunnels.${tunnelId} = {
      credentialsFile = config.sops.secrets."cloudflared.json".path;
      default = "http://127.0.0.1:80";
    };
  };
}
