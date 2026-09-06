{
  config,
  inputs,
  loopbackVhost,
  ...
}:
{
  imports = [ inputs.mixbridge-web.nixosModules.default ];

  services.mixbridge-api = {
    enable = true;
    port = 19400;
    environmentFile = config.sops.secrets."mixbridge.env".path;
  };

  services.caddy.virtualHosts."http://mixbridge.harivan.sh" =
    loopbackVhost config.services.mixbridge-api.port;
}
