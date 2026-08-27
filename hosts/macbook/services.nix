# Every launchd unit the macbook runs, in one place. Model (2026-08-21
# startup audit): nix-darwin launchd is the ONLY service manager this config
# uses - the systemd of this host. Daemons and agents declared here render
# to org.nixos.* plists; nix-darwin unloads and deletes stale ones on
# switch, so removing an entry here is a complete removal.
#
# NOT here on purpose:
# - tailscale: the GUI app's network extension is the node. nix-darwin's
#   services.tailscale ran a second, never-logged-in tailscaled for months
#   (verified 2026-08-21: BackendState NeedsLogin on its own socket while
#   the extension held the tailnet). The signed app also gets sleep/wake +
#   DNS-restore callbacks the nix-store daemon cannot (NetworkExtension
#   entitlement is signed-bundle-only). Cask in ./homebrew.nix.
# - karabiner: its services are SMAppService registrations owned by the app
#   bundle, versioned with the app. Nix launching the settings window at
#   login (the old open-karabiner-elements agent) did nothing for remapping.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Notch strip height (NSScreen.safeAreaInsets.top) for the sketchybar rc.
  # A compiled AppKit binary because `swift -e` JIT-compiles via xcodebuild and
  # blocked the rc for minutes at a cold login (see dots/sketchybar/sketchybarrc).
  notchInset = pkgs.runCommandCC "notch-inset" { } ''
    mkdir -p $out/bin
    $CC -fobjc-arc -framework AppKit -o $out/bin/notch-inset ${./notch-inset/notch-inset.m}
  '';

  home = "/Users/${config.system.primaryUser}";
  customScripts = import ../../pkgs/scripts {
    homeDirectory = home;
    inherit (pkgs) lib;
    inherit pkgs;
  };
  sparkDisplay = customScripts.darwinPackages.spark-display;
  sunshineBin = "/opt/homebrew/opt/sunshine/bin/sunshine";
in
{
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

  # sketchybar replaces the native menu bar (auto-hidden via _HIHideMenuBar);
  # the rc lives in dots/sketchybar and is symlinked to ~/.config/sketchybar
  # by the user activation, so config here stays "" (sketchybar's default
  # lookup path). aerospace is needed on the agent's PATH for the workspace
  # items.
  services.sketchybar = {
    enable = true;
    extraPackages = [
      pkgs.aerospace
      pkgs.sketchybar-app-font # icon_map.sh for the workspace tab app icons
      notchInset # bar height measurement, see the rc
    ];
  };

  # app icon glyphs for the sketchybar workspace tabs
  fonts.packages = [ pkgs.sketchybar-app-font ];

  launchd.user.agents = {
    # AeroSpace as a hand-declared launchd agent, NOT nix-darwin's
    # services.aerospace: that module always renders its own `settings` to a
    # store toml and passes `--config-path`, which overrides the ~/.config
    # lookup. Verified 2026-08-21: the running instance had loaded a 16-line
    # default config with ZERO keybindings while the 174-line dots toml sat
    # unread. This agent passes no --config-path so AeroSpace reads
    # ~/.config/aerospace/aerospace.toml (symlinked to dots, live-edited,
    # reloaded in-app via service mode). The toml sets start-at-login = false
    # so AeroSpace's own SMAppService login item never races this agent.
    aerospace.serviceConfig = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        "/bin/wait4path /nix/store && exec ${pkgs.aerospace}/Applications/AeroSpace.app/Contents/MacOS/AeroSpace"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/Users/${config.system.primaryUser}/Library/Logs/aerospace.log";
      StandardErrorPath = "/Users/${config.system.primaryUser}/Library/Logs/aerospace.log";
    };

    # Log the sketchybar daemon's stdout/stderr (rc failures, plugin errors):
    # nix-darwin's services.sketchybar sets no log path, so the 2026-08-18
    # empty-bar login left nothing to read. Merged with the module's own
    # serviceConfig.
    sketchybar.serviceConfig = {
      StandardOutPath = "/Users/${config.system.primaryUser}/Library/Logs/sketchybar.log";
      StandardErrorPath = "/Users/${config.system.primaryUser}/Library/Logs/sketchybar.log";
    };

    # spark-display cast host (see AGENTS.md "Casting"). Never run sunshine
    # any other way: a second instance steals the ports and this one goes deaf.
    sunshine.serviceConfig = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        "/bin/wait4path ${sunshineBin} && exec ${sunshineBin} ${home}/.config/sunshine/sunshine.conf"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "${home}/Library/Logs/sunshine.log";
      StandardErrorPath = "${home}/Library/Logs/sunshine.log";
    };

    # The spark-display convergence supervisor; PathState = alive exactly
    # while the cast is on, resuming across reboots.
    spark-cast.serviceConfig = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        "/bin/wait4path /nix/store && exec ${sparkDisplay}/bin/spark-display supervise"
      ];
      RunAtLoad = true;
      KeepAlive = {
        PathState."${home}/.local/state/spark-cast/on" = true;
      };
      ThrottleInterval = 5;
      StandardOutPath = "${home}/Library/Logs/spark-cast.log";
      StandardErrorPath = "${home}/Library/Logs/spark-cast.log";
    };
  };

  # One-time migration off `brew services start sunshine` (setup night).
  system.activationScripts.postActivation.text = lib.mkAfter ''
    brewSunshinePlist="${home}/Library/LaunchAgents/homebrew.mxcl.sunshine.plist"
    if [ -f "$brewSunshinePlist" ]; then
      sudo -u ${config.system.primaryUser} /bin/launchctl bootout \
        "gui/$(id -u ${config.system.primaryUser})/homebrew.mxcl.sunshine" 2>/dev/null || true
      rm -f "$brewSunshinePlist"
      echo "removed brew-services sunshine agent (now nix-owned)"
    fi
  '';
}
