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
# - nap-cast + sunshine: declared by the nap flake's sender module,
#   imported in ./nap.nix. Still nix-darwin launchd agents (org.nixos.*),
#   just not spelled out in this file.
{
  config,
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

  # Every dynamic value in the bar, pushed over sketchybar's mach port from one
  # long-lived process (see hosts/macbook/sketchybar-feed/feed.m). Replaced the
  # per-item shell plugins 2026-08-28: those forked a process per tick and the
  # volume one ran `osascript` (a TCC round-trip) on every event. The app-glyph
  # table is generated from sketchybar-app-font's icon_map.sh at build time.
  sketchybarFeed = pkgs.runCommandCC "sketchybar-feed" { } ''
    mkdir -p $out/bin build
    awk -f ${./sketchybar-feed/gen-icon-map.awk} \
      ${pkgs.sketchybar-app-font}/bin/icon_map.sh > build/icon_map.h
    cp ${./sketchybar-feed/feed.m} build/feed.m
    $CC -fobjc-arc -O2 -Wall -Wno-unused-parameter \
      -framework Foundation -framework AppKit -framework CoreAudio \
      -framework AudioToolbox -framework IOKit -framework CoreGraphics \
      -o $out/bin/sketchybar-feed build/feed.m
  '';

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
      notchInset # bar height measurement, see the rc
      sketchybarFeed # `sketchybar-feed volume-event`, the volume item's mouse script
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

    # Sibling of the sketchybar agent: waits for its mach port, then pushes
    # every item value. The rc signals it (SIGUSR1) at the end of each load,
    # aerospace's exec-on-workspace-change signals it (SIGUSR2). aerospace on
    # PATH for the workspace tabs.
    sketchybar-feed.serviceConfig = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        "/bin/wait4path /nix/store && exec ${sketchybarFeed}/bin/sketchybar-feed"
      ];
      EnvironmentVariables.PATH = "${pkgs.aerospace}/bin:/usr/bin:/bin";
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/Users/${config.system.primaryUser}/Library/Logs/sketchybar-feed.log";
      StandardErrorPath = "/Users/${config.system.primaryUser}/Library/Logs/sketchybar-feed.log";
    };

  };
}
