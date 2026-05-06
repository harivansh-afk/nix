{
  config,
  lib,
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
    after = [ "NetworkManager-wait-online.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [
      pkgs.getent
      pkgs.kmod
      pkgs.procps
    ];
    serviceConfig = {
      ExecStart = "${lib.getExe' pkgs.tailscale "tailscaled"} --state=/var/lib/tailscale-ix/tailscaled.state --socket=/run/tailscale-ix/tailscaled.sock --port=41642 --tun=tailscale-ix";
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
    serviceConfig.Type = "notify";
    script = ''
      getState() {
        tailscale --socket /run/tailscale-ix/tailscaled.sock status --json --peers=false | jq -r '.BackendState'
      }

      lastState=""
      while state="$(getState)"; do
        if [[ "$state" != "$lastState" ]]; then
          case "$state" in
            NeedsLogin|NeedsMachineAuth|Stopped)
              echo "Server needs ix.dev authentication, sending auth key"
              tailscale --socket /run/tailscale-ix/tailscaled.sock up --auth-key "$(cat ${
                config.sops.secrets."tailscale-ix-authkey".path
              })" --hostname=spark-ix --accept-dns=false --ssh
              ;;
            Running)
              echo "ix.dev Tailscale is running"
              systemd-notify --ready
              exit 0
              ;;
            *)
              echo "Waiting for ix.dev Tailscale State = Running or systemd timeout"
              ;;
          esac
          echo "State = $state"
        fi
        lastState="$state"
        sleep .5
      done
    '';
  };

  networking.firewall = {
    enable = true;
    allowedUDPPorts = [ 41642 ];
    trustedInterfaces = [
      "tailscale0"
      "tailscale-ix"
    ];
  };

  zramSwap.enable = true;
}
