_: {
  services.caddy = {
    enable = true;
    globalConfig = ''
      auto_https off
    '';
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "rathiharivansh@gmail.com";
  };

  _module.args.loopbackVhost = port: {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      encode zstd gzip
      reverse_proxy 127.0.0.1:${toString port}
    '';
  };
}
