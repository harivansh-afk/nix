{
  config,
  mkSparkSecret,
  ...
}:
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
  sops.secrets."cloudflared-credentials" = mkSparkSecret "cloudflared.json" {
    mode = "0444";
    restartUnits = [ "cloudflared-tunnel-${tunnelId}.service" ];
  };

  services.cloudflared = {
    enable = true;
    tunnels.${tunnelId} = {
      credentialsFile = config.sops.secrets."cloudflared-credentials".path;
      # Cloudflared hands every tunnel request to Caddy on loopback.
      # Caddy dispatches by `Host:` header to the right backend
      # (see modules/services/caddy.nix and the per-service vhosts).
      # Any host not matched by a Caddy vhost falls through to the
      # default 404, which Caddy also handles.
      default = "http://127.0.0.1:80";
      ingress = { };
    };
  };
}
