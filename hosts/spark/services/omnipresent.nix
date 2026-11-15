# omnipresent (git.harivan.sh/harivansh-afk/omnipresent): its own module runs the stack as the owner
# (omnipresent-harnessd, -livekit, -core, -voice; -env builds the Python environment). Deploy a change with
# `nix flake update omnipresent`. This file adds the keys and makes it reachable over the tailnet.
#
# One hostname, tailnet-only, declared the way git.harivan.sh is (forgejo/default.nix): an unproxied A record to
# spark's tailnet address, a certificate by DNS-01 through Cloudflare, Caddy on :443, which the firewall opens on
# tailscale0 only (forgejo/default.nix opens it; flake/tests.nix holds the list to exactly [ 443 ]).
#   https://omni.harivan.sh/web/           -> 127.0.0.1:8790  the dashboard, with /web taken off
#   https://omni.harivan.sh/api/           -> 404             reserved for the API contract; never the dashboard's /api
#   https://omni.harivan.sh/rtc, /twirp/   -> 127.0.0.1:7880  LiveKit signalling (wss) and its server API
#   https://omni.harivan.sh/token, /sync/  -> 127.0.0.1:8780  the phone's endpoints; temporary, they move under /api/
#   https://omni.harivan.sh/               -> /web/           a redirect
#   UDP 7882 on tailscale0                                    LiveKit media, direct
# HTTP/1.1, 2 and 3 (UDP 443 on tailscale0); Caddy to each backend is plain HTTP on loopback.
#
# The older Tailscale Serve addresses stay until the phone app uses the hostname, then go:
#   https://spark.<tailnet>:8780 -> 127.0.0.1:8780  the conductor's token endpoint
#   https://spark.<tailnet>:7443 -> 127.0.0.1:7880  LiveKit signalling (wss)
#   https://spark.<tailnet>:8790 -> 127.0.0.1:8790  the live dashboard (`conductor dash`), read-only
{
  config,
  inputs,
  username,
  ...
}:
let
  tailscale = "${config.services.tailscale.package}/bin/tailscale";
  domain = "omni.harivan.sh";
  # These go once every client uses ${domain}.
  # One unit, applied in order: concurrent `tailscale serve` calls fail on the config's etag.
  routes = [
    {
      port = 8780;
      target = "http://127.0.0.1:8780";
    }
    {
      port = 7443;
      target = "http://127.0.0.1:7880";
    }
    {
      port = 8790;
      target = "http://127.0.0.1:8790";
    }
  ];
in
{
  imports = [ inputs.omnipresent.nixosModules.default ];

  services.omnipresent = {
    enable = true;
    user = username;
    environmentFile = config.sops.secrets."omnipresent.env".path;
    # The desktop's Chromium (services/desktop.nix): agents may drive it, signed in as the owner.
    browserCdpPort = 19222;
  };

  # 443 is HTTP/3: Caddy serves it on every TLS listener unless told not to, so opening the port is all it takes,
  # and it opens for git.harivan.sh too, which shares the listener.
  networking.firewall.interfaces.tailscale0.allowedUDPPorts = [
    443
    7882
  ];

  security.acme.certs.${domain} = {
    dnsProvider = "cloudflare";
    dnsResolver = "1.1.1.1:53";
    credentialFiles.CLOUDFLARE_DNS_API_TOKEN_FILE = config.sops.secrets."cloudflare-api-token".path;
  };

  services.caddy.virtualHosts."https://${domain}" = {
    useACMEHost = domain;
    extraConfig = ''
      encode zstd gzip

      @livekit path /rtc /rtc/* /twirp/*
      handle @livekit {
        reverse_proxy 127.0.0.1:7880
      }

      @phone path /token /sync/*
      handle @phone {
        reverse_proxy 127.0.0.1:8780 {
          flush_interval -1
        }
      }

      @api path /api /api/*
      handle @api {
        respond "The omni API is not served yet." 404
      }

      redir /web /web/ 308
      handle_path /web/* {
        reverse_proxy 127.0.0.1:8790 {
          flush_interval -1
        }
      }

      redir / /web/ 302

      handle {
        respond "Nothing is served at this path." 404
      }
    '';
  };

  systemd.services.omnipresent-tailscale-serve = {
    description = "Tailscale Serve for omnipresent";
    after = [ "tailscaled.service" ];
    requires = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = "${tailscale} wait";
      ExecStart = map (r: "${tailscale} serve --bg --https=${toString r.port} ${r.target}") routes;
      ExecStop = map (r: "${tailscale} serve --https=${toString r.port} off") routes;
    };
  };
}
