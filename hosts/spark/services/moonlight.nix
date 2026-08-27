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
  # Blanking the VT drops the fbcon framebuffer into DPMS off, so the
  # monitor sleeps instead of showing the console. cage relights the
  # output itself when it takes DRM master (wlroots enables the connector
  # on modeset), so there is no unblank counterpart.
  blank = pkgs.writeShellApplication {
    name = "monitor-blank";
    runtimeInputs = [ pkgs.util-linux ];
    text = ''
      exec </dev/tty1 >/dev/tty1
      setterm --term linux --blank force
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
    ExecStopPost = lib.getExe blank;
  };

  # The monitor is dark whenever the kiosk is not running: blanked at boot
  # (after getty settles, so its terminal reset cannot undo the blank) and
  # re-blanked by ExecStopPost after every cast. consoleblank re-blanks
  # after any stray unblank; a keyboard-less console has none in practice.
  boot.kernelParams = [ "consoleblank=15" ];

  systemd.services.monitor-blank = {
    wantedBy = [ "multi-user.target" ];
    after = [ "getty.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe blank;
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
