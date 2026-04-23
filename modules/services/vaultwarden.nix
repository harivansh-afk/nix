{ config, ... }:
let
  vaultDomain = "vault.harivan.sh";
  backendPort = 8222;
in
{
  # Admin token, SMTP creds, etc. Lives in secrets/spark/vaultwarden.env
  # as a binary-encoded KEY=value blob, identical to what was at
  # /var/lib/vaultwarden/vaultwarden.env on netty.
  sops.secrets."vaultwarden-env" = {
    sopsFile = ../../secrets/spark/vaultwarden.env;
    format = "binary";
    owner = "vaultwarden";
    group = "vaultwarden";
    mode = "0400";
    restartUnits = [ "vaultwarden.service" ];
  };

  services.vaultwarden = {
    enable = true;
    backupDir = "/var/backup/vaultwarden";
    environmentFile = config.sops.secrets."vaultwarden-env".path;
    config = {
      DOMAIN = "https://${vaultDomain}";
      SIGNUPS_ALLOWED = false;
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = backendPort;
    };
  };

  # Host-based route: cloudflared tunnel -> Caddy on :80 -> vaultwarden.
  # Using the `http://` scheme prefix tells Caddy this vhost is plain
  # HTTP only (no ACME), which is what we want behind cloudflared.
  services.caddy.virtualHosts."http://${vaultDomain}" = {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      reverse_proxy 127.0.0.1:${toString backendPort}
    '';
  };
}
