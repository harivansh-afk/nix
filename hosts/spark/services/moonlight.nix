# Cast receiver for the mac's extended display: see AGENTS.md "Casting".
# Stream target is /var/lib/spark-cast/host (published by the mac's
# supervisor); no fallback path by design. One-time pairing:
#   sudo -u moonlight env QT_QPA_PLATFORM=offscreen moonlight pair <mac-ip> --pin NNNN
{
  lib,
  pkgs,
  username,
  ...
}:
let
  # A VT blank does not reach DPMS on this NVIDIA fbcon (tested live:
  # setterm --blank force as root, dpms stayed On), so the monitor is put
  # to sleep by forcing the DRM connector off, which drops the HDMI link
  # unconditionally. The force is sticky - wlroots cannot undo it - so
  # cage-tty1 re-probes the connector in ExecStartPre before every cast.
  # Manual recovery if the box is ever dark and unmanaged:
  #   echo detect > /sys/class/drm/card1-HDMI-A-1/status
  connector = "/sys/class/drm/card1-HDMI-A-1/status";
  monitorOff = pkgs.writeShellApplication {
    name = "monitor-off";
    text = ''
      echo off > ${connector}
    '';
  };
  monitorOn = pkgs.writeShellApplication {
    name = "monitor-on";
    text = ''
      echo detect > ${connector}
    '';
  };

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
        host=$(cat /var/lib/spark-cast/host 2>/dev/null || true)
        if [ -n "$host" ]; then
          moonlight stream "$host" Desktop \
            --resolution 3440x1440 \
            --fps 60 \
            --bitrate 30000 \
            --display-mode fullscreen \
            --video-codec HEVC \
            --no-vsync \
            --frame-pacing \
            --audio-on-host \
            --quit-after || true
        fi
        sleep 3
      done
    '';
  };
in
{
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

  systemd.defaultUnit = lib.mkForce "multi-user.target";

  systemd.services."cage-tty1".serviceConfig = {
    KillSignal = "SIGKILL";
    ExecStartPre = lib.getExe monitorOn;
    ExecStopPost = lib.getExe monitorOff;
  };

  systemd.services.monitor-off = {
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe monitorOff;
    };
  };

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
