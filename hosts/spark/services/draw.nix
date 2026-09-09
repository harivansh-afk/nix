{
  config,
  inputs,
  loopbackVhost,
  ...
}:
let
  domain = "draw.harivan.sh";
  port = 34729;
in
{
  imports = [ inputs.draw.nixosModules.default ];

  services.draw = {
    enable = true;
    listen = "127.0.0.1:${toString port}";
    baseUrl = "https://${domain}";
    environmentFile = config.sops.secrets."draw-google-oauth.env".path;
    backup.enable = true;
  };

  services.caddy.virtualHosts."http://${domain}" = (loopbackVhost port) // {
    extraConfig = ''
      @insecure header X-Forwarded-Proto http
      redir @insecure https://${domain}{uri} 308
      header Strict-Transport-Security "max-age=31536000"
      encode zstd gzip
      reverse_proxy 127.0.0.1:${toString port} {
        trusted_proxies 127.0.0.1
        header_up X-Forwarded-Proto https
        header_up X-Forwarded-For {http.request.header.CF-Connecting-IP}
        header_up CF-Connecting-IP {http.request.header.CF-Connecting-IP}
      }
    '';
  };
}
