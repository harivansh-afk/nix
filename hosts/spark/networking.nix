{
  config,
  username,
  ...
}:
{

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
      "--accept-dns"
      "--operator=${username}"
      "--ssh=false"
    ];
  };

  zramSwap.enable = true;
}
