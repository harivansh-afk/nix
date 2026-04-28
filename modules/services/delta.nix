{
  config,
  mkSparkSecret,
  pkgs,
  username,
  loopbackVhost,
  ...
}:
let
  deltaDomain = "delta.harivan.sh";
  deltaPort = 3300;
  stateDir = "/var/lib/delta";
  repoDir = "/home/${username}/Documents/GitHub/delta";
  dbPath = "${stateDir}/data.db";
in
{
  services.caddy.virtualHosts."http://${deltaDomain}" = loopbackVhost deltaPort;

  sops.secrets."delta-env" = mkSparkSecret "delta.env" {
    owner = username;
    group = "users";
    mode = "0400";
    restartUnits = [ "delta.service" ];
  };

  systemd.tmpfiles.rules = [
    "d ${stateDir} 0750 ${username} users -"
  ];

  systemd.services.delta = {
    description = "Delta - Self-hosted Todo Platform";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      NODE_ENV = "production";
      HOSTNAME = "127.0.0.1";
      PORT = toString deltaPort;
      DATABASE_URL = dbPath;
      OAUTH_REDIRECT_BASE_URL = "https://${deltaDomain}";
      WEBAUTHN_ORIGIN = "https://${deltaDomain}";
      WEBAUTHN_RP_ID = deltaDomain;
    };

    path = [ pkgs.nodejs_24 ];

    serviceConfig = {
      Type = "simple";
      User = username;
      Group = "users";
      WorkingDirectory = repoDir;
      ExecStart = "${repoDir}/node_modules/.bin/next start --port ${toString deltaPort} --hostname 127.0.0.1";
      EnvironmentFile = config.sops.secrets."delta-env".path;
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

}
