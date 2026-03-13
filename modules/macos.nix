{
  lib,
  pkgs,
  ...
}: let
  karabinerAgentsDir =
    "${pkgs.karabiner-elements}/Library/Application Support/org.pqrs/Karabiner-Elements/"
    + "Karabiner-Elements Non-Privileged Agents v2.app/Contents/Library/LaunchAgents";
in {
  security.pam.services.sudo_local.touchIdAuth = true;

  services.karabiner-elements.enable = true;

  # Karabiner-Elements 15.7.0 moved its user launch agents into the
  # Non-Privileged Agents v2 bundle and renamed karabiner_grabber.
  # nix-darwin's built-in module still points at the old top-level paths.
  environment.userLaunchAgents."org.pqrs.karabiner.agent.karabiner_grabber.plist".enable =
    lib.mkForce false;
  environment.userLaunchAgents."org.pqrs.karabiner.agent.karabiner_observer.plist".enable =
    lib.mkForce false;
  environment.userLaunchAgents."org.pqrs.karabiner.karabiner_console_user_server.plist".enable =
    lib.mkForce false;

  environment.userLaunchAgents."org.pqrs.service.agent.Karabiner-Core-Service.plist".source = "${karabinerAgentsDir}/org.pqrs.service.agent.Karabiner-Core-Service.plist";
  environment.userLaunchAgents."org.pqrs.service.agent.Karabiner-NotificationWindow.plist".source = "${karabinerAgentsDir}/org.pqrs.service.agent.Karabiner-NotificationWindow.plist";
  environment.userLaunchAgents."org.pqrs.service.agent.Karabiner-Menu.plist".source = "${karabinerAgentsDir}/org.pqrs.service.agent.Karabiner-Menu.plist";
  environment.userLaunchAgents."org.pqrs.service.agent.karabiner_console_user_server.plist".source = "${karabinerAgentsDir}/org.pqrs.service.agent.karabiner_console_user_server.plist";
  environment.userLaunchAgents."org.pqrs.service.agent.Karabiner-MultitouchExtension.plist".source = "${karabinerAgentsDir}/org.pqrs.service.agent.Karabiner-MultitouchExtension.plist";

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
