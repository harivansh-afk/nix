{ config, ... }:
{
  security.pam.services.sudo_local.touchIdAuth = true;

  # Karabiner-Elements is managed via Homebrew cask because nix-darwin's
  # built-in module is broken with 15.7+ (missing karabiner_grabber/observer binaries).

  system.defaults.smb.NetBIOSName = builtins.substring 0 15 config.networking.hostName;
  system.defaults.smb.ServerDescription = config.networking.hostName;

  launchd.daemons."limit.maxfiles" = {
    serviceConfig = {
      Label = "limit.maxfiles";
      ProgramArguments = [
        "/bin/launchctl"
        "limit"
        "maxfiles"
        "65536"
        "200000"
      ];
      RunAtLoad = true;
      KeepAlive = false;
    };
  };

  system.defaults = {
    dock.autohide = true;
    dock.show-recents = false;

    NSGlobalDomain = {
      ApplePressAndHoldEnabled = false;
      InitialKeyRepeat = 15;
      KeyRepeat = 2;
    };
  };
}
