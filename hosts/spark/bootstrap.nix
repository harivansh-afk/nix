{ config, pkgs, ... }:
let
  bootstrapDir = "/var/lib/spark-bootstrap";
  wifiEnvFile = "${bootstrapDir}/network-manager.env";
  wifiConnectionName = "spark-bootstrap-wifi";
  tailscaleAuthKeyFile = "${bootstrapDir}/tailscale-authkey";
  tailscaleBin = "${config.services.tailscale.package}/bin/tailscale";
in
{
  # `nixos-anywhere --extra-files tmp/spark-bootstrap` copies optional
  # bootstrap secrets into the installed system. This keeps first-boot
  # Wi-Fi and Tailscale enrollment out of the Nix store.
  systemd.tmpfiles.rules = [
    "d ${bootstrapDir} 0700 root root -"
  ];

  systemd.services.spark-bootstrap-wifi = {
    description = "Install bootstrap Wi-Fi profile";
    after = [ "NetworkManager.service" ];
    wants = [ "NetworkManager.service" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = wifiEnvFile;
    path = with pkgs; [
      bash
      coreutils
      gnugrep
      networkmanager
    ];
    serviceConfig = {
      Type = "oneshot";
    };
    script = ''
      if ! grep -q '^SPARK_WIFI_SSID=' "${wifiEnvFile}" || ! grep -q '^SPARK_WIFI_PSK=' "${wifiEnvFile}"; then
        echo "Expected SPARK_WIFI_SSID and SPARK_WIFI_PSK in ${wifiEnvFile}" >&2
        exit 0
      fi

      set -a
      source "${wifiEnvFile}"
      set +a

      if [ -z "''${SPARK_WIFI_SSID:-}" ] || [ -z "''${SPARK_WIFI_PSK:-}" ]; then
        echo "Bootstrap Wi-Fi variables are empty in ${wifiEnvFile}" >&2
        exit 0
      fi

      install -d -m 700 /etc/NetworkManager/system-connections
      cat > /etc/NetworkManager/system-connections/${wifiConnectionName}.nmconnection <<EOF
      [connection]
      id=${wifiConnectionName}
      type=wifi
      autoconnect=true

      [wifi]
      mode=infrastructure
      ssid=$SPARK_WIFI_SSID

      [wifi-security]
      auth-alg=open
      key-mgmt=wpa-psk
      psk=$SPARK_WIFI_PSK

      [ipv4]
      method=auto

      [ipv6]
      addr-gen-mode=stable-privacy
      method=auto
      EOF

      chmod 600 /etc/NetworkManager/system-connections/${wifiConnectionName}.nmconnection
      nmcli connection reload
      nmcli --wait 10 connection up ${wifiConnectionName} || true
    '';
  };

  systemd.services.spark-bootstrap-tailscale = {
    description = "Join Tailscale with bootstrap auth key";
    after = [
      "tailscaled.service"
      "spark-bootstrap-wifi.service"
    ];
    wants = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = tailscaleAuthKeyFile;
    path = with pkgs; [
      coreutils
      jq
    ];
    serviceConfig = {
      Type = "oneshot";
    };
    script = ''
      auth_key="$(tr -d '\n' < "${tailscaleAuthKeyFile}")"
      if [ -z "$auth_key" ]; then
        exit 0
      fi

      backend_state="$(${tailscaleBin} status --json 2>/dev/null | jq -r '.BackendState // ""' || true)"
      if [ -n "$backend_state" ] && [ "$backend_state" != "NeedsLogin" ]; then
        exit 0
      fi

      ${tailscaleBin} up \
        --auth-key "$auth_key" \
        --ssh
    '';
  };
}
