# omnipresent (git.harivan.sh/harivansh-afk/omnipresent): its own module runs the stack as the owner
# (omnipresent-harnessd, -livekit, -core, -voice; -env builds the Python environment). Deploy a change with
# `nix flake update omnipresent`. This file adds the keys and makes it reachable from the phone over the tailnet:
#   https://spark.<tailnet>:8780 -> 127.0.0.1:8780  the conductor's token endpoint
#   https://spark.<tailnet>:7443 -> 127.0.0.1:7880  LiveKit signalling (wss)
#   https://spark.<tailnet>:8790 -> 127.0.0.1:8790  the live dashboard (`conductor dash`), read-only
#   UDP 7882 on tailscale0                           LiveKit media
{
  config,
  inputs,
  username,
  ...
}:
let
  tailscale = "${config.services.tailscale.package}/bin/tailscale";
  domain = "omni.harivan.sh";
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

      handle_path /api/* {
        reverse_proxy 127.0.0.1:8800 {
          flush_interval -1
        }
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
