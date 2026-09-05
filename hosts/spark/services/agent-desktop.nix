{ pkgs, username, ... }:
let
  browser = pkgs.writeShellScriptBin "agent-browser" ''
    exec ${pkgs.chromium}/bin/chromium --ozone-platform=wayland --password-store=gnome-libsecret \
      --user-data-dir="$HOME/.local/share/agent-desktop/chromium" "$@"
  '';
  desktop = pkgs.writeShellApplication {
    name = "agent-desktop";
    runtimeInputs = with pkgs; [
      sway
      grim
      wtype
    ];
    text = ''
      XDG_RUNTIME_DIR="/run/user/$(id -u)"
      export XDG_RUNTIME_DIR
      export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
      export SWAYSOCK="$XDG_RUNTIME_DIR/agent-desktop/sway.sock"
      if [[ -r "$XDG_RUNTIME_DIR/agent-desktop/wayland-display" ]]; then
        WAYLAND_DISPLAY=$(cat "$XDG_RUNTIME_DIR/agent-desktop/wayland-display")
        export WAYLAND_DISPLAY
      fi
      case "''${1:-status}" in
        status) systemctl --user status agent-desktop ;;
        screenshot) grim -o HEADLESS-1 "''${2:-/tmp/agent-desktop.png}" ;;
        type) shift; wtype -s 100 -- "$@" ;;
        key) shift; wtype -s 100 "$@" -s 100 ;;
        move) swaymsg seat seat0 cursor set "$2" "$3" ;;
        click)
          swaymsg seat seat0 cursor press "''${2:-button1}"
          swaymsg seat seat0 cursor release "''${2:-button1}"
          ;;
        exec) shift; exec "$@" ;;
        *) echo 'Usage: agent-desktop {status|screenshot [path]|type text|key wtype-args|move x y|click [button1]|exec command...}' >&2; exit 2 ;;
      esac
    '';
  };
  session = pkgs.writeShellScript "agent-desktop-session" ''
    printf '%s\n' "$WAYLAND_DISPLAY" > "$XDG_RUNTIME_DIR/agent-desktop/wayland-display"
    ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
    ${pkgs.foot}/bin/foot &
    ${browser}/bin/agent-browser &
    exec ${pkgs.wayvnc}/bin/wayvnc --output=HEADLESS-1 127.0.0.1 45931
  '';
  swayConfig = pkgs.writeText "agent-desktop-sway.conf" ''
    xwayland disable
    output HEADLESS-1 mode 1600x1000
    output HEADLESS-1 bg #202020 solid_color
    seat seat0 fallback true
    default_border pixel 2
    font monospace 12
    bindsym Mod4+Return exec ${pkgs.foot}/bin/foot
    bindsym Mod4+b exec ${browser}/bin/agent-browser
    bindsym Mod4+Shift+q kill
    bindsym Mod4+f fullscreen toggle
    bindsym Mod4+Left focus left
    bindsym Mod4+Right focus right
    exec ${session}
  '';
in
{
  environment.systemPackages = [
    browser
    desktop
    pkgs.foot
  ];
  fonts.packages = [ pkgs.dejavu_fonts ];
  services.gnome.gnome-keyring.enable = true;

  systemd.user.services.agent-desktop = {
    description = "Agent Wayland desktop";
    wantedBy = [ "default.target" ];
    unitConfig.ConditionUser = username;
    environment = {
      WLR_BACKENDS = "headless";
      WLR_HEADLESS_OUTPUTS = "1";
      WLR_RENDERER = "pixman";
      WLR_LIBINPUT_NO_DEVICES = "1";
      SWAYSOCK = "%t/agent-desktop/sway.sock";
      XDG_CURRENT_DESKTOP = "sway";
      XDG_SESSION_TYPE = "wayland";
    };
    serviceConfig = {
      ExecStart = "${pkgs.sway}/bin/sway --unsupported-gpu --config ${swayConfig}";
      Restart = "on-failure";
      RestartSec = 3;
      RuntimeDirectory = "agent-desktop";
      RuntimeDirectoryMode = "0700";
      UMask = "0077";
    };
  };
}
