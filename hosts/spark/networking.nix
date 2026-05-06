{
  config,
  mkSparkSecret,
  pkgs,
  ...
}:
{
  sops.secrets."wifi.env" = mkSparkSecret "wifi.env" {
    restartUnits = [ "NetworkManager-ensure-profiles.service" ];
  };

  networking.networkmanager = {
    enable = true;
    ensureProfiles = {
      environmentFiles = [ config.sops.secrets."wifi.env".path ];
      profiles.spark-wifi = {
        connection = {
          id = "spark-wifi";
          type = "wifi";
          autoconnect = true;
        };
        wifi = {
          mode = "infrastructure";
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

  sops.secrets."tailscale-authkey" = mkSparkSecret "tailscale-authkey" {
    owner = "root";
    mode = "0400";
  };

  sops.secrets."tailscale-ix-authkey" = mkSparkSecret "tailscale-ix-authkey" {
    owner = "root";
    mode = "0400";
    restartUnits = [ "tailscaled-ix-autoconnect.service" ];
  };

  services.tailscale = {
    enable = true;
    authKeyFile = config.sops.secrets."tailscale-authkey".path;
    useRoutingFeatures = "server";
    openFirewall = true;
    extraUpFlags = [
      "--advertise-tags=tag:shared"
      "--ssh"
    ];
  };

  systemd.services.tailscaled-ix = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.tailscale}/bin/tailscaled --tun=userspace-networking --socket=/run/tailscale-ix/tailscaled.sock --state=/var/lib/tailscale-ix/tailscaled.state --port=41642 --socks5-server=127.0.0.1:1055 --outbound-http-proxy-listen=127.0.0.1:1056";
      Restart = "on-failure";
      RuntimeDirectory = "tailscale-ix";
      StateDirectory = "tailscale-ix";
    };
  };

  systemd.services.tailscaled-ix-autoconnect = {
    after = [ "tailscaled-ix.service" ];
    wants = [ "tailscaled-ix.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [
      pkgs.jq
      pkgs.tailscale
    ];
    serviceConfig.Type = "oneshot";
    script = ''
      state="$(tailscale --socket=/run/tailscale-ix/tailscaled.sock status --json --peers=false | jq -r '.BackendState')"
      case "$state" in
        Running)
          exit 0
          ;;
        NeedsLogin|NeedsMachineAuth|Stopped)
          tailscale --socket=/run/tailscale-ix/tailscaled.sock up \
            --auth-key "$(cat ${config.sops.secrets."tailscale-ix-authkey".path})" \
            --hostname spark-ix \
            --accept-dns=false \
            --ssh=false
          ;;
      esac
    '';
  };

  networking.firewall = {
    enable = true;
    trustedInterfaces = [ "tailscale0" ];
  };

  zramSwap.enable = true;
}
