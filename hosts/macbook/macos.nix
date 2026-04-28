{ config, lib, ... }:
let
  loginApps = [
    "Raycast"
    "PastePal"
    "Ghostty"
    "Karabiner-Elements"
    "Tailscale"
    "Wispr Flow"
  ];
in
{
  security.pam.services.sudo_local.touchIdAuth = true;

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

  system.defaults.dock = {
    autohide = true;
    show-recents = false;
  };

  system.defaults.finder = {
    FXPreferredViewStyle = "Nlsv";
    FXDefaultSearchScope = "SCcf";
    AppleShowAllExtensions = true;
    ShowPathbar = true;
    ShowStatusBar = true;
    _FXSortFoldersFirst = true;
    FXEnableExtensionChangeWarning = false;
    FXRemoveOldTrashItems = true;
    QuitMenuItem = true;
    ShowExternalHardDrivesOnDesktop = true;
    ShowRemovableMediaOnDesktop = true;
  };

  system.defaults.NSGlobalDomain = {
    ApplePressAndHoldEnabled = false;
    InitialKeyRepeat = 15;
    KeyRepeat = 2;

    NSAutomaticCapitalizationEnabled = false;
    NSAutomaticSpellingCorrectionEnabled = false;
    NSAutomaticDashSubstitutionEnabled = false;
    NSAutomaticQuoteSubstitutionEnabled = false;
    NSAutomaticPeriodSubstitutionEnabled = false;
    NSAutomaticInlinePredictionEnabled = false;

    AppleShowAllExtensions = true;
    NSDocumentSaveNewDocumentsToCloud = false;
    NSNavPanelExpandedStateForSaveMode = true;
    NSNavPanelExpandedStateForSaveMode2 = true;
  };

  system.defaults.screencapture = {
    location = "~/Desktop/screenshots";
    type = "png";
    disable-shadow = true;
  };

  system.activationScripts.screenshotsDir.text = ''
    sudo -u ${config.system.primaryUser} /bin/mkdir -p /Users/${config.system.primaryUser}/Desktop/screenshots
  '';

  launchd.user.agents = builtins.listToAttrs (
    map (app: {
      name = "open-${lib.strings.toLower (builtins.replaceStrings [ " " ] [ "-" ] app)}";
      value.serviceConfig = {
        Program = "/usr/bin/open";
        ProgramArguments = [
          "/usr/bin/open"
          "-a"
          app
        ];
        RunAtLoad = true;
        KeepAlive = false;
      };
    }) loginApps
  );

  services.tailscale.enable = true;
}
