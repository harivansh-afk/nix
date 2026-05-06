{
  config,
  mkSparkSecret,
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

  networking.firewall = {
    enable = true;
    trustedInterfaces = [ "tailscale0" ];
  };

  zramSwap.enable = true;
}
