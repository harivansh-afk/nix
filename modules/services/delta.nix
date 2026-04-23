{
  config,
  pkgs,
  username,
  ...
}:
let
  deltaDomain = "delta.harivan.sh";
  deltaPort = "3300";
  stateDir = "/var/lib/delta";
  repoDir = "/home/${username}/Documents/GitHub/delta";
  dbPath = "${stateDir}/data.db";
in
{
  # INTEGRATION_ENCRYPTION_KEY etc. Same contents as netty's
  # /var/lib/delta/delta.env, now encrypted in-repo.
  sops.secrets."delta-env" = {
    sopsFile = ../../secrets/spark/delta.env;
    format = "binary";
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
      PORT = deltaPort;
      DATABASE_URL = dbPath;
      OAUTH_REDIRECT_BASE_URL = "https://${deltaDomain}";
      WEBAUTHN_ORIGIN = "https://${deltaDomain}";
      WEBAUTHN_RP_ID = deltaDomain;
    };

    path = [ pkgs.nodejs_22 ];

    serviceConfig = {
      Type = "simple";
      User = username;
      Group = "users";
      WorkingDirectory = repoDir;
      ExecStart = "${repoDir}/node_modules/.bin/next start --port ${deltaPort} --hostname 127.0.0.1";
      EnvironmentFile = config.sops.secrets."delta-env".path;
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  # Host-based route through Caddy on loopback.
  services.caddy.virtualHosts."http://${deltaDomain}" = {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      reverse_proxy 127.0.0.1:${deltaPort}
    '';
  };
}
