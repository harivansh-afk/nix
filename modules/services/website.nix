{
  username,
  ...
}:
let
  domain = "harivan.sh";
  repoDir = "/home/${username}/Documents/Git/website";
  mountDir = "/srv/harivan.sh";
  serveDir = "${mountDir}/dist";
in
{
  services.caddy.virtualHosts."http://${domain}" = {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      root * ${serveDir}
      handle /status-badge {
        rewrite * /badge
        reverse_proxy https://status.${domain} {
          header_up Host status.${domain}
        }
      }
      handle {
        file_server
      }
      handle_errors {
        @notFound expression {err.status_code} == 404
        rewrite @notFound /404.html
        file_server
      }
    '';
  };

  systemd.services.caddy.serviceConfig.BindReadOnlyPaths = [ "${repoDir}:${mountDir}" ];
}
