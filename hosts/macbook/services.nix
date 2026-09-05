{
  config,
  pkgs,
  ...
}:
let
  # Notch strip height for the sketchybar rc. Compiled, because `swift -e`
  # JIT-compiles through xcodebuild and blocked the rc for minutes at login.
  notchInset = pkgs.runCommandCC "notch-inset" { } ''
    mkdir -p $out/bin
    $CC -fobjc-arc -framework AppKit -o $out/bin/notch-inset ${./notch-inset/notch-inset.m}
  '';

  # Every dynamic value in the bar, pushed over sketchybar's mach port from one
  # daemon (no per-item shell plugins). The app-glyph table is generated from
  # sketchybar-app-font's icon_map.sh at build time.
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
    };
  };

  # The rc is the live-edited dots/sketchybar symlink, so no config here.
  services.sketchybar = {
    enable = true;
    extraPackages = [
      pkgs.aerospace
      notchInset
      sketchybarFeed # the volume item's mouse script
    ];
  };

  fonts.packages = [ pkgs.sketchybar-app-font ];

  launchd.user.agents = {
    # Hand-declared, not services.aerospace: that module passes its own
    # --config-path and silently overrides the dots toml. No config flag
    # here, so AeroSpace reads the live ~/.config/aerospace/aerospace.toml.
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

    # services.sketchybar sets no log path.
    sketchybar.serviceConfig = {
      StandardOutPath = "/Users/${config.system.primaryUser}/Library/Logs/sketchybar.log";
      StandardErrorPath = "/Users/${config.system.primaryUser}/Library/Logs/sketchybar.log";
    };

    # Waits for sketchybar's mach port, then pushes every item value. The rc
    # signals it with SIGUSR1 after each load, aerospace with SIGUSR2 on
    # workspace change.
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
