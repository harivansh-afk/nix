{ config, ... }:
let
  # Tunnel UUID returned by the one-time `POST /cfd_tunnel` call that
  # provisioned this tunnel in the Rathiharivansh@gmail.com CF account.
  # The matching credentials (AccountTag, TunnelID, TunnelSecret) live
  # encrypted at secrets/spark/cloudflared.json and are mounted at
  # /run/secrets/cloudflared-credentials on boot.
  tunnelId = "64bce32c-6613-459c-bb68-262d73e1b78f";
in
{
  # The upstream `services.cloudflared` module runs the tunnel under a
  # systemd DynamicUser, so there is no static `cloudflared` account to
  # chown the secret to. We leave the file root:root and grant world-read
  # (0444) so the ephemeral DynamicUser can still open it. Acceptable
  # because the credentials are already scoped to a single tunnel in a
  # personal Cloudflare account and the host is single-tenant.
  sops.secrets."cloudflared-credentials" = {
    sopsFile = ../../secrets/spark/cloudflared.json;
    format = "binary";
    mode = "0444";
    restartUnits = [ "cloudflared-tunnel-${tunnelId}.service" ];
  };

  services.cloudflared = {
    enable = true;
    tunnels.${tunnelId} = {
      credentialsFile = config.sops.secrets."cloudflared-credentials".path;
      # Catch-all until Phase 3 per-service ingress rules are wired in.
      default = "http_status:404";
      ingress = { };
    };
  };
}
