{
  config,
  lib,
  pkgs,
  ...
}:
let
  ixAuthKeyPath = config.sops.secrets."tailscale-ix-authkey".path;
  ixStateDir = "/Users/${config.system.primaryUser}/.local/state/tailscale-ix";
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

  system.activationScripts.tailscaleIxDirs.text = ''
    sudo -u ${config.system.primaryUser} /bin/mkdir -p ${ixStateDir}
  '';

  sops.secrets."tailscale-ix-authkey" = {
    sopsFile = ../../secrets/spark/tailscale-ix-authkey;
    format = "binary";
    owner = config.system.primaryUser;
    mode = "0400";
  };

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
      tailscaled-ix = {
        serviceConfig = {
          ProgramArguments = [
            "${pkgs.tailscale}/bin/tailscaled"
            "--tun=userspace-networking"
            "--socket=${ixStateDir}/tailscaled.sock"
            "--state=${ixStateDir}/tailscaled.state"
            "--port=41642"
            "--socks5-server=127.0.0.1:1055"
            "--outbound-http-proxy-listen=127.0.0.1:1056"
          ];
          RunAtLoad = true;
          KeepAlive = true;
          StandardOutPath = "${ixStateDir}/tailscaled.log";
          StandardErrorPath = "${ixStateDir}/tailscaled.log";
        };
      };

      tailscaled-ix-autoconnect = {
        serviceConfig = {
          ProgramArguments = [
            "/bin/sh"
            "-lc"
            ''
              if [ ! -r ${lib.escapeShellArg ixAuthKeyPath} ]; then
                exit 0
              fi
              state="$(${pkgs.tailscale}/bin/tailscale --socket=${lib.escapeShellArg "${ixStateDir}/tailscaled.sock"} status --json --peers=false | ${pkgs.jq}/bin/jq -r '.BackendState')" || exit 0
              case "$state" in
                Running)
                  exit 0
                  ;;
                NeedsLogin|NeedsMachineAuth|Stopped)
                  ${pkgs.tailscale}/bin/tailscale --socket=${lib.escapeShellArg "${ixStateDir}/tailscaled.sock"} up --auth-key "$(cat ${lib.escapeShellArg ixAuthKeyPath})" --hostname macbook-ix --accept-dns=false --ssh=false
                  ;;
              esac
            ''
          ];
          RunAtLoad = true;
          StartInterval = 60;
          StandardOutPath = "${ixStateDir}/autoconnect.log";
          StandardErrorPath = "${ixStateDir}/autoconnect.log";
        };
      };
    };

  services.tailscale.enable = true;
}
