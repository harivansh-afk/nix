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

      # HTML is never cached, so a visitor always gets the current page (which
      # points at the latest content-hashed asset URLs). Assets are content-
      # hashed at build time, so they can be cached forever and bust on change.
      @html path / */ *.html
      header @html Cache-Control "no-cache"
      @assets path *.css *.js *.woff *.woff2 *.ttf *.otf *.png *.jpg *.jpeg *.gif *.svg *.ico *.webp
      header @assets Cache-Control "public, max-age=31536000, immutable"

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
