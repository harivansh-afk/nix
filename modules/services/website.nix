{
  username,
  ...
}:
let
  domain = "harivan.sh";
  repoDir = "/home/${username}/Documents/GitHub/website";
  mountDir = "/srv/harivan.sh";
  serveDir = "${mountDir}/dist";
in
{
  services.caddy.virtualHosts."http://${domain}" = {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      root * ${serveDir}
      file_server
      handle_errors {
        @notFound expression {err.status_code} == 404
        rewrite @notFound /404.html
        file_server
      }
    '';
  };

  systemd.services.caddy.serviceConfig.BindReadOnlyPaths = [ "${repoDir}:${mountDir}" ];
}
