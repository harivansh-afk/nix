# the website: one build (the live checkout's dist/), two domains. hari.cafe
# is the personal site; harivan.sh is the developer screen, which is its
# root and nothing else: every other harivan.sh path redirects to the same
# path on hari.cafe, and hari.cafe/developer/ redirects to harivan.sh. both
# share the hashed assets, fonts and views.json.
#
# view counts need no service: caddy answers the page beacon itself and
# writes each hit, without ip or headers, to its own log, and the website's
# tools/views.mjs sums that log into dist/views.json on every build and on a
# timer between builds.
{ pkgs, username, ... }:
let
  cafe = "hari.cafe";
  dev = "harivan.sh";
  repoDir = "/home/${username}/Documents/Git/website";
  mountDir = "/srv/harivan.sh";
  # never rolled: the counts are rebuilt from the whole log every run
  hitsLog = "/var/log/caddy/${dev}-hits.log";

  # what both domains serve the same way
  common = ''
    root * ${mountDir}/dist

    # HTML always revalidates; assets are content-hashed and cache forever.
    @html path / */ *.html
    header @html Cache-Control "no-cache"
    @assets path *.css *.js *.woff *.woff2 *.ttf *.otf *.png *.jpg *.jpeg *.gif *.svg *.ico *.webp
    header @assets Cache-Control "public, max-age=31536000, immutable"
    # rewritten every few minutes by website-views
    header /views.json Cache-Control "no-cache"

    # the view beacon: POST /counter/hit?p=<path>[&e=1] from either domain
    @hit {
      method POST
      path /counter/hit
      header Origin https://${cafe}
      header Origin https://${dev}
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
      reverse_proxy https://status.${dev} {
        header_up Host status.${dev}
      }
    }
    handle_errors {
      header Cache-Control "no-cache"
      @notFound expression {err.status_code} == 404
      rewrite @notFound /404.html
      file_server
    }
  '';
in
{
  services.caddy.virtualHosts."http://${cafe}" = {
    serverAliases = [ "http://www.${cafe}" ];
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      # only requests routed here by log_name (the beacon) reach this log.
      # defined once, here; the harivan.sh block routes to it by name
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

      ${common}

      # the developer screen lives on harivan.sh
      handle /developer* {
        redir https://${dev}/ 301
      }
      handle {
        file_server
      }
    '';
  };

  services.caddy.virtualHosts."http://${dev}" = {
    serverAliases = [ "http://www.${dev}" ];
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      ${common}

      # the root is the developer screen (the website's reroute hook hydrates
      # it as that route); the rest of the site is on hari.cafe
      handle / {
        rewrite * /developer/index.html
        file_server
      }
      handle /developer* {
        redir https://${dev}/ 301
      }
      @shared path /_app/* /fonts/* /views.json /icon.svg /og.png /favicon.ico /robots.txt
      handle @shared {
        file_server
      }
      handle {
        redir https://${cafe}{uri} 301
      }
    '';
  };

  systemd.services.caddy.serviceConfig.BindReadOnlyPaths = [ "${repoDir}:${mountDir}" ];

  # the hit log is caddy:caddy 0640; ./build.sh reads it as this user
  users.users.${username}.extraGroups = [ "caddy" ];

  # refresh the counts between builds
  systemd.services.website-views = {
    description = "website view counts";
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
