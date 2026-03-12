{...}: {
  security.pam.services.sudo_local.touchIdAuth = true;

  services.karabiner-elements.enable = true;

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
