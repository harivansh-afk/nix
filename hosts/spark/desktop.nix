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
    "usbhid"
  ];

  environment.systemPackages = [
    pkgs.firefox-bin
    pkgs.ghostty
  ];

  environment.sessionVariables.NIXOS_OZONE_WL = "1";
}
