{ lib, ... }:
let
  loginApps = [
    "VoiceInk"
  ];
in
{
  launchd.user.agents =
    builtins.listToAttrs (
      map (app: {
        name = "open-${lib.strings.toLower (builtins.replaceStrings [ " " ] [ "-" ] app)}";
        value.serviceConfig = {
          ProgramArguments = [
            "/usr/bin/open"
            "-a"
            "/Applications/${app}.app"
          ];
          RunAtLoad = true;
        };
      }) loginApps
    )
    // {
      open-pastepal.serviceConfig = {
        ProgramArguments = [ "/Applications/PastePal.app/Contents/MacOS/PastePal" ];
        RunAtLoad = true;
        KeepAlive = true;
        ProcessType = "Interactive";
      };
    };
}
