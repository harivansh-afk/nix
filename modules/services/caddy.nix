{ lib, ... }:
{
  services.caddy = {
    enable = true;
    globalConfig = ''
      auto_https off
    '';
  };

  _module.args.loopbackVhost = port: {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      reverse_proxy 127.0.0.1:${toString port}
    '';
  };
}
