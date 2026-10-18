{
  config,
  pkgs,
  ...
}:
let

  notchInset = pkgs.runCommandCC "notch-inset" { } ''
    mkdir -p $out/bin
    $CC -fobjc-arc -framework AppKit -o $out/bin/notch-inset ${./notch-inset/notch-inset.m}
  '';

  sketchybarFeed = pkgs.runCommandCC "sketchybar-feed" { } ''
    mkdir -p $out/bin
    $CC -fobjc-arc -O2 -Wall -Wno-unused-parameter \
      -framework Foundation -framework AppKit -framework CoreAudio \
      -framework AudioToolbox -framework IOKit -framework CoreGraphics \
      -o $out/bin/sketchybar-feed ${./sketchybar-feed/feed.m}
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

  services.sketchybar = {
    enable = true;
    extraPackages = [
      pkgs.aerospace
      notchInset
      sketchybarFeed
    ];
  };

  launchd.user.agents = {

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

    sketchybar.serviceConfig = {
      StandardOutPath = "/Users/${config.system.primaryUser}/Library/Logs/sketchybar.log";
      StandardErrorPath = "/Users/${config.system.primaryUser}/Library/Logs/sketchybar.log";
    };

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
