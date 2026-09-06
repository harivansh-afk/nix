{
  config,
  pkgs,
  username,
  ...
}:
let
  cuaDriver = pkgs.callPackage ../../../pkgs/cua-driver { };
  computer = import ../../../pkgs/spark-computer { inherit pkgs; };
  chromium = pkgs.chromium.override {
    commandLineArgs = "--ozone-platform=wayland --password-store=gnome-libsecret --force-renderer-accessibility --remote-debugging-port=19222";
  };
  swayConfig = pkgs.writeText "sway.conf" ''
    xwayland disable
    output HEADLESS-1 mode 1600x1000
    output HEADLESS-1 bg #202020 solid_color
    seat seat0 fallback true
    bindsym Mod4+Return exec ${pkgs.ghostty}/bin/ghostty
    bindsym Mod4+b exec ${chromium}/bin/chromium
    bindsym Mod1+Return exec ${pkgs.ghostty}/bin/ghostty
    bindsym Mod1+b exec ${chromium}/bin/chromium
    bindsym Mod4+Shift+q kill
    bindsym Mod4+f fullscreen toggle
    bindsym Mod4+Left focus left
    bindsym Mod4+Right focus right
    exec ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd WAYLAND_DISPLAY SWAYSOCK XDG_CURRENT_DESKTOP XDG_SESSION_TYPE GTK_A11Y NO_AT_BRIDGE && ${pkgs.systemd}/bin/systemctl --user start wayvnc cua-driver chromium
    exec ${pkgs.ghostty}/bin/ghostty
  '';
in
{
  environment.systemPackages = [
    chromium
    computer
    cuaDriver
    pkgs.ghostty
    pkgs.sway
    pkgs.grim
    pkgs.wtype
  ];
  fonts.packages = [ pkgs.dejavu_fonts ];
  services.dbus.packages = [ pkgs.at-spi2-core ];
  systemd.packages = [ pkgs.at-spi2-core ];
  systemd.user.tmpfiles.users.${username}.rules = [
    "L+ %h/.config/sway-mimeapps.list - - - - ${pkgs.writeText "sway-mimeapps.list" ''
      [Default Applications]
      text/html=chromium-browser.desktop
      x-scheme-handler/http=chromium-browser.desktop
      x-scheme-handler/https=chromium-browser.desktop
    ''}"
  ];
  services.gnome.gnome-keyring.enable = true;
  programs.dconf.enable = true;
  programs.dconf.profiles.user.databases = [
    {
      settings."org/gnome/desktop/interface".toolkit-accessibility = true;
    }
  ];
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.sway.default = [ "gtk" ];
  };

  systemd.user.services.cua-driver = {
    description = "Cua desktop automation";
    partOf = [ "sway.service" ];
    after = [ "sway.service" ];
    unitConfig.ConditionUser = username;
    environment = {
      CUA_DRIVER_RS_ENABLE_WAYLAND = "1";
      CUA_DRIVER_RS_TELEMETRY_ENABLED = "0";
      XDG_SESSION_TYPE = "wayland";
    };
    serviceConfig = {
      ExecStart = "${cuaDriver}/bin/cua-driver serve --socket %t/cua-driver/control.sock";
      RuntimeDirectory = "cua-driver";
      RuntimeDirectoryMode = "0700";
      Restart = "on-failure";
      RestartSec = 3;
      UMask = "0077";
    };
  };

  systemd.user.services.chromium = {
    description = "Chromium agent desktop browser";
    partOf = [ "sway.service" ];
    after = [ "sway.service" ];
    unitConfig.ConditionUser = username;
    environment = {
      GTK_A11Y = "always";
      NO_AT_BRIDGE = "0";
    };
    serviceConfig = {
      ExecStart = "${chromium}/bin/chromium --restore-last-session";
      Restart = "always";
      RestartSec = 3;
      UMask = "0077";
    };
  };

  systemd.user.services.wayvnc = {
    description = "WayVNC remote desktop";
    environment.XKB_DEFAULT_OPTIONS = "altwin:meta_win";
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
      GTK_A11Y = "always";
      NO_AT_BRIDGE = "0";
    };
    serviceConfig = {
      ExecStart = "${pkgs.sway}/bin/sway --unsupported-gpu --config ${swayConfig}";
      Restart = "on-failure";
      RestartSec = 3;
      UMask = "0077";
    };
  };
}
