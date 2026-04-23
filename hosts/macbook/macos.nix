{ config, lib, ... }:
let
  # Apps to auto-launch at login via launchd user agents.
  # Declarative replacement for System Settings → Login Items.
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

  # ── Dock ────────────────────────────────────────────────────────────
  system.defaults.dock = {
    autohide = true;
    show-recents = false;
  };

  # ── Finder ──────────────────────────────────────────────────────────
  system.defaults.finder = {
    FXPreferredViewStyle = "Nlsv"; # list view
    FXDefaultSearchScope = "SCcf"; # search current folder
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

  # ── Global preferences ─────────────────────────────────────────────
  system.defaults.NSGlobalDomain = {
    ApplePressAndHoldEnabled = false;
    InitialKeyRepeat = 15;
    KeyRepeat = 2;

    # Kill the auto-correct suite — terminals, chat, code comments.
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

  # ── Screenshots ─────────────────────────────────────────────────────
  # Directory is created on activation so `screencapture` doesn't silently
  # fall back to ~/Desktop when the folder is missing.
  system.defaults.screencapture = {
    location = "~/Desktop/screenshots";
    type = "png";
    disable-shadow = true;
  };

  system.activationScripts.screenshotsDir.text = ''
    sudo -u ${config.system.primaryUser} /bin/mkdir -p /Users/${config.system.primaryUser}/Desktop/screenshots
  '';

  # ── Login items ─────────────────────────────────────────────────────
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

  # ── Services ────────────────────────────────────────────────────────
  # Enables the Tailscale daemon (tailscaled). The Tailscale.app menu-bar
  # UI can still run alongside; the daemon replaces its bundled one.
  services.tailscale.enable = true;
}
