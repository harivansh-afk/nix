{
  config,
  lib,
  pkgs,
  ...
}:
let
  loginApps = [
    "Raycast"
    "PastePal"
    "Ghostty"
    "Karabiner-Elements"
    "Tailscale"
    # VoiceInk autostart lives here (launchd), NOT in the app's own
    # "Launch at Login" toggle: that uses SMAppService, whose registration
    # goes stale every time the ad-hoc source build is re-signed.
    "VoiceInk"
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

  # sketchybar replaces the native menu bar (auto-hidden below); the rc lives
  # in dots/sketchybar and is symlinked to ~/.config/sketchybar by the user
  # activation, so config here stays "" (sketchybar's default lookup path).
  # aerospace is needed on the agent's PATH for the workspace items.
  services.sketchybar = {
    enable = true;
    extraPackages = [
      pkgs.aerospace
      pkgs.sketchybar-app-font # icon_map.sh for the workspace tab app icons
    ];
  };

  # app icon glyphs for the sketchybar workspace tabs
  fonts.packages = [ pkgs.sketchybar-app-font ];

  system.defaults.NSGlobalDomain = {
    _HIHideMenuBar = true;
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

  launchd.user.agents =
    builtins.listToAttrs (
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
    )
    // {
      # Respawn mux sessions at login. mux already writes a `.restore` marker
      # per live server (removed on stop/kill); this agent only triggers
      # `mux restore` so marked sessions come back before a terminal is opened.
      # TMPDIR is resolved explicitly because mux derives its socket dir from it
      # on darwin and the agent must agree with login shells. AbandonProcessGroup
      # keeps the spawned nvim servers alive after the agent exits.
      mux-restore.serviceConfig = {
        ProgramArguments = [
          "/bin/sh"
          "-c"
          ''export TMPDIR="''${TMPDIR:-$(getconf DARWIN_USER_TEMP_DIR)}"; exec /run/current-system/sw/bin/mux restore''
        ];
        RunAtLoad = true;
        KeepAlive = false;
        AbandonProcessGroup = true;
        EnvironmentVariables.PATH = "/run/current-system/sw/bin:/usr/bin:/bin";
      };
    };

  services.tailscale.enable = true;
}
