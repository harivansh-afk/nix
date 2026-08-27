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
  # unconditionally. The counterpart is force-connected, never `detect`:
  # after a force-off, nvidia-drm's reprobe reads disconnected with the
  # monitor attached (tested live: cage came up with zero outputs and
  # moonlight streamed into a placeholder screen), so probing can never
  # be trusted to relight. Forcing is sticky in both directions and
  # wlroots cannot undo it; cage-tty1 forces on in ExecStartPre before
  # every cast. Manual recovery if the box is ever dark and unmanaged:
  #   echo on > /sys/class/drm/card1-HDMI-A-1/status
  # The write triggers a reprobe and can block indefinitely while DRM
  # state is in flux (observed: ExecStopPost hung for the full 90s stop
  # timeout during a switch-aborted start, SIGKILL, unit failed, and the
  # failed unit failed the whole activation - deploys #6262/#6266). Both
  # hooks are best-effort with a hard timeout: a missed force costs one
  # lit console, never a wedged stop or a failed switch.
  # tee, not `sh -c 'echo > f'`: the unit PATH has no sh (deploy #6277
  # logged `timeout: failed to run command 'sh'`), and timeout needs a
  # child process to bound the potentially-blocking sysfs write.
  connector = "/sys/class/drm/card1-HDMI-A-1/status";
  monitorOff = pkgs.writeShellApplication {
    name = "monitor-off";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      echo off | timeout 10 tee ${connector} >/dev/null || true
    '';
  };
  monitorOn = pkgs.writeShellApplication {
    name = "monitor-on";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      echo on | timeout 10 tee ${connector} >/dev/null || true
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

  # Only the spark-cast supervisor ever starts the kiosk. The cage module
  # wants it from graphical.target, and graphical.target is active on this
  # box, so every nixos-rebuild switch started the kiosk unasked (cast off,
  # monitor lit) and raced its own activation - both deploy failures on
  # 2026-08-27 were this. Empty wants makes the unit strictly on-demand.
  # The hooks carry systemd's "+" prefix: cage-tty1 runs as User=moonlight
  # and Exec hooks inherit that, so without it every connector write died
  # on EPERM behind the || true - the force-on in ExecStartPre had never
  # actually executed (deploy #6277's journal: "Permission denied").
  # SuccessExitStatus=SIGKILL: the kiosk is stopped by SIGKILL on purpose,
  # and without this every stop left the unit "failed", which also failed
  # any activation that stopped it. stopIfChanged=false keeps switches
  # from interrupting a live cast at all - unit changes apply on the next
  # natural kiosk restart.
  systemd.services."cage-tty1" = {
    wantedBy = lib.mkForce [ ];
    stopIfChanged = false;
    serviceConfig = {
      KillSignal = "SIGKILL";
      SuccessExitStatus = "SIGKILL";
      ExecStartPre = "+${lib.getExe monitorOn}";
      ExecStopPost = "+${lib.getExe monitorOff}";
    };
  };

  systemd.targets.graphical.wants = lib.mkForce [ ];

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
