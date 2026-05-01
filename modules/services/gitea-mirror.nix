{
  config,
  inputs,
  loopbackVhost,
  mkSparkSecret,
  ...
}:
let
  mirrorDomain = "mirror.harivan.sh";
  backendPort = 19301;
in
{
  imports = [ inputs.gitea-mirror.nixosModules.default ];

  services.caddy.virtualHosts."http://${mirrorDomain}" = loopbackVhost backendPort;

  sops.secrets."gitea-mirror.env" = mkSparkSecret "gitea-mirror.env" {
    owner = "gitea-mirror";
    group = "gitea-mirror";
    mode = "0400";
    restartUnits = [ "gitea-mirror.service" ];
  };

  services.gitea-mirror = {
    enable = true;
    host = "127.0.0.1";
    port = backendPort;
    betterAuthUrl = "https://${mirrorDomain}";
    betterAuthTrustedOrigins = "https://${mirrorDomain}";
    environmentFile = config.sops.secrets."gitea-mirror.env".path;
    openFirewall = false;
  };
}
