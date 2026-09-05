{
  config,
  pkgs,
  username,
  ...
}:
let
  chromium = pkgs.chromium.override {
    commandLineArgs = "--ozone-platform=wayland --password-store=gnome-libsecret";
  };
  swayConfig = pkgs.writeText "sway.conf" ''
    xwayland disable
    output HEADLESS-1 mode 1600x1000
    output HEADLESS-1 bg #202020 solid_color
    seat seat0 fallback true
    bindsym Mod4+Return exec ${pkgs.foot}/bin/foot
    bindsym Mod4+b exec ${chromium}/bin/chromium
    bindsym Mod4+Shift+q kill
    bindsym Mod4+f fullscreen toggle
    bindsym Mod4+Left focus left
    bindsym Mod4+Right focus right
    exec ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd WAYLAND_DISPLAY SWAYSOCK XDG_CURRENT_DESKTOP && ${pkgs.systemd}/bin/systemctl --user start wayvnc
    exec ${pkgs.foot}/bin/foot
    exec ${chromium}/bin/chromium
  '';
in
{
  environment.systemPackages = [
    chromium
    pkgs.foot
    pkgs.sway
    pkgs.grim
    pkgs.wtype
  ];
  fonts.packages = [ pkgs.dejavu_fonts ];
  services.gnome.gnome-keyring.enable = true;

  systemd.user.services.wayvnc = {
    description = "WayVNC remote desktop";
    partOf = [ "sway.service" ];
    after = [ "sway.service" ];
    unitConfig.ConditionUser = username;
    serviceConfig = {
      ExecStart = "${pkgs.wayvnc}/bin/wayvnc --config ${
        config.sops.secrets."wayvnc.conf".path
      } 100.114.116.11 45931";
      Restart = "on-failure";
      RestartSec = 5;
      UMask = "0077";
    };
  };

  systemd.user.services.sway = {
    description = "Sway desktop";
    wantedBy = [ "default.target" ];
    path = [ pkgs.bash ];
    unitConfig.ConditionUser = username;
    environment = {
      WLR_BACKENDS = "headless";
      WLR_RENDERER = "pixman";
      XDG_CURRENT_DESKTOP = "sway";
      XDG_SESSION_TYPE = "wayland";
    };
    serviceConfig = {
      ExecStart = "${pkgs.sway}/bin/sway --unsupported-gpu --config ${swayConfig}";
      Restart = "on-failure";
      RestartSec = 3;
      UMask = "0077";
    };
  };
}
