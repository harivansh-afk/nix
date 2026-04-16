{
  pkgs,
  username,
  ...
}:
let
  deltaPort = "3300";
  stateDir = "/var/lib/delta";
  repoDir = "/home/${username}/Documents/GitHub/delta";
  envFile = "${stateDir}/delta.env";
  dbPath = "${stateDir}/data.db";
in
{
  systemd.tmpfiles.rules = [
    "d ${stateDir} 0750 ${username} users -"
    "z ${envFile} 0600 ${username} users -"
  ];

  systemd.services.delta = {
    description = "Delta - Self-hosted Todo Platform";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      NODE_ENV = "production";
      HOSTNAME = "127.0.0.1";
      PORT = deltaPort;
      DATABASE_URL = dbPath;
      OAUTH_REDIRECT_BASE_URL = "https://delta.harivan.sh";
      WEBAUTHN_ORIGIN = "https://delta.harivan.sh";
      WEBAUTHN_RP_ID = "delta.harivan.sh";
    };

    path = [ pkgs.nodejs_22 ];

    serviceConfig = {
      Type = "simple";
      User = username;
      Group = "users";
      WorkingDirectory = repoDir;
      ExecStart = "${repoDir}/node_modules/.bin/next start --port ${deltaPort} --hostname 127.0.0.1";
      EnvironmentFile = "-${envFile}";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
