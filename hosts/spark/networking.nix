{
  config,
  pkgs,
  ...
}:
let
  personalSocket = "/run/tailscale-personal/tailscaled.sock";
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
      profiles.spark-wifi = {
        connection = {
          id = "spark-wifi";
          type = "wifi";
          autoconnect = true;
        };
        wifi = {
          bssid = "58:FB:96:A1:58:41";
          mode = "infrastructure";
          powersave = 2;
          ssid = "$WIFI_SSID";
        };
        wifi-security = {
          auth-alg = "open";
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

  services.tailscale = {
    enable = true;
    authKeyFile = config.sops.secrets."tailscale-ix-authkey".path;
    extraUpFlags = [
      "--hostname=spark-ix"
      "--accept-dns=false"
      "--ssh=false"
    ];
  };

  systemd.services.tailscaled-personal = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.tailscale}/bin/tailscaled --tun=userspace-networking --socket=${personalSocket} --state=/var/lib/tailscale-personal/tailscaled.state --port=41642 --socks5-server=127.0.0.1:1055 --outbound-http-proxy-listen=127.0.0.1:1056";
      Restart = "on-failure";
      RuntimeDirectory = "tailscale-personal";
      StateDirectory = "tailscale-personal";
    };
  };

  environment.systemPackages = [
    (pkgs.writeShellScriptBin "tailscale-personal" ''
      exec ${pkgs.tailscale}/bin/tailscale --socket=${personalSocket} "$@"
    '')
  ];

  networking.firewall.enable = true;

  zramSwap.enable = true;
}
