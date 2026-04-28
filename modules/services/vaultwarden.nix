{
  config,
  loopbackVhost,
  mkSparkSecret,
  ...
}:
let
  vaultDomain = "vault.harivan.sh";
  backendPort = 8222;
in
{
  services.caddy.virtualHosts."http://${vaultDomain}" = loopbackVhost backendPort;

  # Admin token, SMTP creds, etc. — sourced as a binary-encoded
  # KEY=value blob from secrets/spark/vaultwarden.env.
  sops.secrets."vaultwarden-env" = mkSparkSecret "vaultwarden.env" {
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
}
