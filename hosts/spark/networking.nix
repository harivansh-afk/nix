{ config, ... }:
{
  # --- Wi-Fi (declarative via NetworkManager ensureProfiles) ---------------
  #
  # The SSID + PSK live in `secrets/spark/wifi.env` as a KEY=value blob;
  # sops-nix decrypts it to /run/secrets/wifi.env at activation and the
  # systemd oneshot NetworkManager ships (`NetworkManager-ensure-profiles`)
  # interpolates `$WIFI_SSID` / `$WIFI_PSK` via envsubst before writing
  # the managed profile. Rotating the PSK is `just sops-edit
  # secrets/spark/wifi.env` + a rebuild — no --extra-files dance.

  sops.secrets."wifi.env" = {
    sopsFile = ../../secrets/spark/wifi.env;
    format = "binary";
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

  # --- Tailscale -----------------------------------------------------------
  #
  # `authKeyFile` is consumed by the upstream module's
  # `tailscaled-autoconnect.service` on first boot if the node isn't
  # already authenticated. Generate a reusable + preauthorized + tagged
  # key at https://login.tailscale.com/admin/settings/keys and rotate
  # via `just sops-edit secrets/spark/tailscale-authkey`.

  sops.secrets."tailscale-authkey" = {
    sopsFile = ../../secrets/spark/tailscale-authkey;
    format = "binary";
    owner = "root";
    mode = "0400";
  };

  services.tailscale = {
    enable = true;
    authKeyFile = config.sops.secrets."tailscale-authkey".path;
    # "server" lets this host act as a subnet router / exit node later
    # without needing another rebuild. No routes are advertised until
    # `tailscale up --advertise-routes=...` is run imperatively.
    useRoutingFeatures = "server";
    openFirewall = true;
  };

  networking.firewall = {
    enable = true;
    # `podman+` is trusted by the upstream dgx-spark module already so
    # containers can reach host services. tailscale0 is trusted so LAN
    # services addressed over the tailnet aren't firewalled.
    trustedInterfaces = [ "tailscale0" ];
  };

  # Better memory behaviour than the 2G swap partition under load.
  zramSwap.enable = true;
}
