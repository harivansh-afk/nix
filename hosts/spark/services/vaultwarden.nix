{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  securityPkgs = import inputs.nixpkgs-security { system = pkgs.stdenv.hostPlatform.system; };
  vaultDomain = "vault.harivan.sh";
  backendPort = 8222;
in
{
  services.caddy.virtualHosts."http://${vaultDomain}" = {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      @insecure header X-Forwarded-Proto http
      redir @insecure https://${vaultDomain}{uri} 308
      header Strict-Transport-Security "max-age=31536000"
      encode zstd gzip
      reverse_proxy 127.0.0.1:${toString backendPort}
    '';
  };

  systemd.services.vaultwarden.preStart = lib.mkBefore ''
    if [ -f /var/lib/vaultwarden/db.sqlite3 ] && [ ! -f /var/lib/vaultwarden/upgrade-backups/pre-1.37.db ]; then
      ${pkgs.coreutils}/bin/install -d -m 0700 /var/lib/vaultwarden/upgrade-backups
      ${pkgs.sqlite}/bin/sqlite3 /var/lib/vaultwarden/db.sqlite3 ".backup '/var/lib/vaultwarden/upgrade-backups/pre-1.37.db.tmp'"
      ${pkgs.coreutils}/bin/chmod 0600 /var/lib/vaultwarden/upgrade-backups/pre-1.37.db.tmp
      ${pkgs.coreutils}/bin/mv /var/lib/vaultwarden/upgrade-backups/pre-1.37.db.tmp /var/lib/vaultwarden/upgrade-backups/pre-1.37.db
    fi
  '';

  services.vaultwarden = {
    enable = true;
    package = securityPkgs.vaultwarden;
    webVaultPackage = securityPkgs.vaultwarden.webvault;
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
