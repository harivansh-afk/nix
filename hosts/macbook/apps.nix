# GUI apps nix launches at login. Apps with their own launch-at-login
# (Raycast, PastePal, Tailscale) are not duplicated here; launch by absolute
# path so LaunchServices cannot resolve a stray bundle of the same name.
{ lib, ... }:
let
  loginApps = [
    "VoiceInk"
  ];
in
{
  launchd.user.agents = builtins.listToAttrs (
    map (app: {
      name = "open-${lib.strings.toLower (builtins.replaceStrings [ " " ] [ "-" ] app)}";
      value.serviceConfig = {
        ProgramArguments = [
          "/usr/bin/open"
          "-a"
          "/Applications/${app}.app"
        ];
        RunAtLoad = true;
        KeepAlive = false;
      };
    }) loginApps
  );
}
