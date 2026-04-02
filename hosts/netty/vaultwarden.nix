{
  ...
}:
let
  vaultDomain = "vault.harivan.sh";
in
{
  systemd.tmpfiles.rules = [
    "z /var/lib/vaultwarden/vaultwarden.env 0600 vaultwarden vaultwarden -"
  ];

  services.vaultwarden = {
    enable = true;
    backupDir = "/var/backup/vaultwarden";
    environmentFile = "/var/lib/vaultwarden/vaultwarden.env";
    config = {
      DOMAIN = "https://${vaultDomain}";
      SIGNUPS_ALLOWED = false;
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = 8222;
    };
  };
}
