{ ... }:
{
  security.pam.services.sudo_local.touchIdAuth = true;

  # Karabiner-Elements is managed via Homebrew cask because nix-darwin's
  # built-in module is broken with 15.7+ (missing karabiner_grabber/observer binaries).

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
