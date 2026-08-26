{
  config,
  loopbackVhost,
  ...
}:
let
  vaultDomain = "vault.harivan.sh";
  backendPort = 8222;
in
{
  services.caddy.virtualHosts."http://${vaultDomain}" = loopbackVhost backendPort;

  services.vaultwarden = {
    enable = true;
    backupDir = "/var/backup/vaultwarden";
    environmentFile = config.sops.secrets."vaultwarden.env".path;
    config = {
      DOMAIN = "https://${vaultDomain}";
      SIGNUPS_ALLOWED = false;
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = backendPort;
    };
  };
}
