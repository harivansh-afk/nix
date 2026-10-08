# harivan.sh: caddy serves the live website checkout's dist/. view counts need
# no service: caddy answers the page beacon itself and writes each hit, without
# ip or headers, to its own log, and the website's tools/views.mjs sums that
# log into dist/views.json on every build and on a timer between builds.
{ pkgs, username, ... }:
let
  domain = "harivan.sh";
  repoDir = "/home/${username}/Documents/Git/website";
  mountDir = "/srv/harivan.sh";
  # never rolled: the counts are rebuilt from the whole log every run
  hitsLog = "/var/log/caddy/${domain}-hits.log";
in
{
  services.caddy.virtualHosts."http://${domain}" = {
    serverAliases = [
      "http://hari.cafe"
      "http://www.hari.cafe"
    ];
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      root * ${mountDir}/dist

      # only requests routed here by log_name (the beacon) reach this log
      log hits {
        no_hostname
        output file ${hitsLog} {
          mode 0640
          roll_disabled
        }
        format filter {
          request>remote_ip delete
          request>remote_port delete
          request>client_ip delete
          request>headers delete
          request>tls delete
          resp_headers delete
          user_id delete
          wrap json
        }
      }

      # HTML always revalidates; assets are content-hashed and cache forever.
      @html path / */ *.html
      header @html Cache-Control "no-cache"
      @assets path *.css *.js *.woff *.woff2 *.ttf *.otf *.png *.jpg *.jpeg *.gif *.svg *.ico *.webp
      header @assets Cache-Control "public, max-age=31536000, immutable"
      # rewritten every few minutes by website-views
      header /views.json Cache-Control "no-cache"

      # the view beacon: POST /counter/hit?p=<path>[&e=1] from the site itself,
      # under either of its domains (hari.cafe is fronted by cloudflare)
      @hit {
        method POST
        path /counter/hit
        header Origin https://${domain}
        header Origin https://hari.cafe
      }
      handle @hit {
        log_name hits
        respond 204
      }
      handle /counter/hit {
        respond 403
      }
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
        header Cache-Control "no-cache"
        @notFound expression {err.status_code} == 404
        rewrite @notFound /404.html
        file_server
      }
    '';
  };

  systemd.services.caddy.serviceConfig.BindReadOnlyPaths = [ "${repoDir}:${mountDir}" ];

  # the hit log is caddy:caddy 0640; ./build.sh reads it as this user
  users.users.${username}.extraGroups = [ "caddy" ];

  # refresh the counts between builds
  systemd.services.website-views = {
    description = "harivan.sh view counts";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    environment.WEBSITE_HITS_LOG = hitsLog;
    serviceConfig = {
      Type = "oneshot";
      User = username;
      WorkingDirectory = repoDir;
      ExecStart = "${pkgs.nodejs_24}/bin/node tools/views.mjs";
      NoNewPrivileges = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ "${repoDir}/dist" ];
    };
  };
  systemd.timers.website-views = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*:0/10";
      Persistent = true;
    };
  };
}
