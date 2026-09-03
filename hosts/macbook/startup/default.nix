# Startup guard: login items and launchd plists nix cannot declare. Runs at
# login, on every switch and daily. Login items outside `loginItems` are
# deleted through System Events (first run may prompt for Automation once);
# launchd plists outside org.nixos.* and `plists` only log and notify.
{ config, pkgs, ... }:
let
  loginItems = [
    "Raycast Beta"
  ];
  plists = [
    "limit.maxfiles.plist"
    "systems.determinate.nix-daemon.plist"
    "systems.determinate.nix-installer.nix-hook.plist"
    "systems.determinate.nix-store.plist"
    "org.nixos.darwin-store.plist"
  ];
  log = "/Users/${config.system.primaryUser}/Library/Logs/startup-guard.log";

  guard = pkgs.writeShellScript "startup-guard" ''
    export LOGIN_ITEMS='|${builtins.concatStringsSep "|" loginItems}|'
    export PLISTS='|${builtins.concatStringsSep "|" plists}|'
    exec ${./guard.sh}
  '';
in
{
  launchd.user.agents.startup-guard.serviceConfig = {
    ProgramArguments = [
      "/bin/sh"
      "-c"
      "/bin/wait4path /nix/store && exec ${guard}"
    ];
    RunAtLoad = true;
    StartCalendarInterval = [
      {
        Hour = 4;
        Minute = 40;
      }
    ];
    StandardOutPath = log;
    StandardErrorPath = log;
  };
}
