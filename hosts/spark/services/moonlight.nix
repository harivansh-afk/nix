# Cast receiver: the mac (Sunshine host) extends its desktop onto spark's
# HDMI monitor. Spark is the Moonlight *client* - it decodes and displays,
# nothing more. The kiosk is cage (wlroots, same stack Hyprland proved on
# this driver) running moonlight-qt fullscreen on tty1.
#
# The unit is deliberately NOT started at boot: the monitor shows the
# console until the mac asks for it. The spark-cast supervisor on the mac
# (pkgs/scripts/bin/spark-display.sh, agent in hosts/macbook/services.nix)
# starts/stops the unit over ssh; the polkit rule below is what lets it do
# that without sudo.
#
# Stream target: LAN-direct first, tailscale fallback. mDNS is blocked on
# the office network (verified: no reply to a direct 224.0.0.251 query), so
# .local is not an option; instead the spark-cast supervisor publishes the
# mac's current LAN IP to /var/lib/spark-cast/host every time it changes,
# and the retry loop alternates that IP with the tailscale IP. Same wifi =
# no WireGuard hop; foreign network = tailscale still works. Pairing is
# cert-based, not IP-based, so both paths share one pairing.
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
  macbookTailscale = "100.96.2.106";

  # HEVC: hardware encode (VideoToolbox) and decode on both ends, sharper
  # text per bit than H.264. Decode path verified live: NVDEC through
  # NVIDIA's VAAPI driver, direct-rendered on wayland ("Using VAAPI
  # accelerated renderer on wayland"); PREFER_VULKAN was dropped after it
  # lost that race anyway and cost ~3.4s of Vulkan device probing per
  # connect. 30 Mbps + --frame-pacing: the double-wifi path drops packets
  # at 45 Mbps (visible breakup), and frame pacing buys ~a frame of buffer
  # against the measured 20ms jitter. --no-vsync stays: a wayland
  # compositor cannot tear, and vsync would add up to 16ms for nothing.
  # --audio-on-host keeps sound on the mac; SDL_AUDIODRIVER=dummy stops
  # moonlight from retrying ALSA every second on a box with no audio
  # server (journal spam).
  kiosk = pkgs.writeShellApplication {
    name = "moonlight-kiosk";
    runtimeInputs = [
      pkgs.moonlight-qt
      pkgs.coreutils
    ];
    text = ''
      export QT_QPA_PLATFORM=wayland
      export SDL_AUDIODRIVER=dummy
      while true; do
        for host in "$(cat /var/lib/spark-cast/host 2>/dev/null || true)" ${macbookTailscale}; do
          [ -n "$host" ] || continue
          moonlight stream "$host" Desktop \
            --resolution 3440x1440 \
            --fps 60 \
            --bitrate 30000 \
            --display-mode fullscreen \
            --video-codec HEVC \
            --no-vsync \
            --frame-pacing \
            --audio-on-host \
            --quit-after && break
        done
        sleep 3
      done
    '';
  };
in
{
  # The supervisor on the mac (as ${username}) publishes the mac's current
  # LAN IP here; the moonlight user only reads it.
  systemd.tmpfiles.rules = [
    "d /var/lib/spark-cast 0755 ${username} users -"
  ];

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

  # cage ignores SIGTERM here (observed: 90s of stop-sigterm limbo, then
  # SIGKILL, and one restart raced the dying instance for the DRM device).
  # The kiosk is stateless; kill it fast.
  systemd.services."cage-tty1".serviceConfig.TimeoutStopSec = 5;

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
