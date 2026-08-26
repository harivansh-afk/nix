{ pkgs, ... }:
{
  programs.hyprland.enable = true;

  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --remember --cmd Hyprland";
      user = "greeter";
    };
  };

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  boot.kernelModules = [
    "hid_generic"
    "uinput"
    "usbhid"
  ];

  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [ "*" ];
      settings.main = {
        capslock = "overload(control, esc)";
        esc = "grave";
        leftalt = "leftmeta";
        leftmeta = "leftalt";
        rightalt = "rightmeta";
        rightmeta = "rightalt";
      };
    };
  };

  environment.systemPackages = [
    pkgs.firefox-bin
    pkgs.ghostty
  ];

  programs.dconf.enable = true;
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

  environment.sessionVariables.NIXOS_OZONE_WL = "1";
}
