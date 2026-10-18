{
  config,
  pkgs,
  ...
}:
let
  ixSocket = "/run/tailscale-ix/tailscaled.sock";
in
{
  # Run a local stub resolver (127.0.0.53) so a resolver is always listening,
  # even before NetworkManager has finished writing upstream nameservers into
  # /etc/resolv.conf at boot. This removes the DNS race that previously killed
  # cloudflared on startup (it queried [::1]:53 before resolv.conf was populated
  # and got "connection refused"), makes nss-lookup.target a meaningful ordering
  # barrier, and adds DNS caching so the upstream router is no longer a single
  # point of failure for name resolution.
  services.resolved.enable = true;

  networking.networkmanager = {
    enable = true;
    dns = "systemd-resolved";
    ensureProfiles = {
      environmentFiles = [ config.sops.secrets."wifi.env".path ];
      profiles = {
        spark-wifi = {
          connection = {
            id = "spark-wifi";
            type = "wifi";
            autoconnect-priority = 10;
          };
          wifi = {
            band = "a";
            powersave = 2;
            ssid = "$WIFI_SSID";
          };
          wifi-security = {
            key-mgmt = "wpa-psk";
            psk = "$WIFI_PSK";
          };
          ipv4.method = "auto";
          ipv6 = {
            addr-gen-mode = "stable-privacy";
            method = "auto";
          };
        };
        spark-wifi-fallback = {
          connection = {
            id = "spark-wifi-fallback";
            type = "wifi";
          };
          wifi = {
            powersave = 2;
            ssid = "$WIFI_SSID";
          };
          wifi-security = {
            key-mgmt = "wpa-psk";
            psk = "$WIFI_PSK";
          };
          ipv4.method = "auto";
          ipv6 = {
            addr-gen-mode = "stable-privacy";
            method = "auto";
          };
        };
      };
    };
  };

  services.tailscale = {
    enable = true;
    extraSetFlags = [
      "--hostname=spark"
      "--accept-dns=false"
      "--ssh=false"
    ];
  };

  systemd.services.tailscaled-ix = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.tailscale}/bin/tailscaled --tun=userspace-networking --socket=${ixSocket} --state=/var/lib/tailscale-ix/tailscaled.state --port=41642";
      Restart = "on-failure";
      RuntimeDirectory = "tailscale-ix";
      StateDirectory = "tailscale-ix";
    };
  };

  environment.systemPackages = [
    (pkgs.writeShellScriptBin "tailscale-ix" ''
      exec ${pkgs.tailscale}/bin/tailscale --socket=${ixSocket} "$@"
    '')
  ];

  zramSwap.enable = true;
}
