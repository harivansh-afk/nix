# Cast receiver: the mac (Sunshine host) extends its desktop onto spark's
# HDMI monitor. Spark is the Moonlight *client* - it decodes and displays,
# nothing more. The kiosk is cage (wlroots, same stack Hyprland proved on
# this driver) running moonlight-qt fullscreen on tty1.
#
# The unit is deliberately NOT started at boot: the monitor shows the
# console until the mac asks for it. The `spark-display` script on the mac
# (pkgs/scripts/bin/spark-display.sh) opens DeskPad and starts/stops the
# unit over ssh; the polkit rule below is what lets it do that without sudo.
#
# Stream target is the mac's tailscale IP: stable across DHCP leases and
# networks, and the tailnet path to the mac is direct (verified). If the
# WireGuard hop ever shows up in the stats overlay, interface-scoped mDNS
# (macbook.local) is the successor.
#
# One-time pairing (PIN confirmed in Sunshine's web UI on the mac):
#   sudo -u moonlight env QT_QPA_PLATFORM=offscreen moonlight pair 100.96.2.106
{
  lib,
  pkgs,
  username,
  ...
}:
let
  macbook = "100.96.2.106";

  # HEVC: hardware encode (VideoToolbox) and decode (NVDEC/Vulkan) on both
  # ends, sharper text per bit than H.264. 45 Mbps fits the office Wi-Fi;
  # raise it if spark ever gets a wire. --no-vsync/--no-frame-pacing is the
  # lowest-latency mode; trade it for --frame-pacing if Wi-Fi jitter shows
  # as judder. --audio-on-host keeps sound on the mac, where an extended
  # display's audio belongs (and spark runs no audio server).
  kiosk = pkgs.writeShellApplication {
    name = "moonlight-kiosk";
    runtimeInputs = [
      pkgs.moonlight-qt
      pkgs.coreutils
    ];
    text = ''
      export QT_QPA_PLATFORM=wayland
      export PREFER_VULKAN=1
      while true; do
        moonlight stream ${macbook} Desktop \
          --resolution 3440x1440 \
          --fps 60 \
          --bitrate 45000 \
          --display-mode fullscreen \
          --video-codec HEVC \
          --no-vsync \
          --no-frame-pacing \
          --audio-on-host \
          --quit-after || true
        sleep 3
      done
    '';
  };
in
{
  users.groups.moonlight = { };
  users.users.moonlight = {
    isNormalUser = true;
    group = "moonlight";
    home = "/var/lib/moonlight";
    createHome = true;
    homeMode = "0700";
    extraGroups = [ "video" ];
  };

  services.cage = {
    enable = true;
    user = "moonlight";
    program = lib.getExe kiosk;
    environment.WLR_LIBINPUT_NO_DEVICES = "1";
  };

  # The cage module force-boots graphical.target (kiosk at power-on). Spark
  # stays a headless server that *can* cast: default back to multi-user and
  # let cage-tty1 be started on demand.
  systemd.defaultUnit = lib.mkForce "multi-user.target";

  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          action.lookup("unit") == "cage-tty1.service" &&
          subject.user == "${username}") {
        return polkit.Result.YES;
      }
    });
  '';

  environment.systemPackages = [ pkgs.moonlight-qt ];
}
