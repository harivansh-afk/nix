{
  lib,
  pkgs,
  username,
  ...
}:
let
  domain = "com.prakashjoshipax.VoiceInk";
  settings = builtins.fromJSON (builtins.readFile ../../../dots/voiceink/settings.json);
  applyData = pkgs.writeShellScript "voiceink-settings" (
    "set -euo pipefail\n"
    + lib.concatStringsSep "\n" (
      lib.mapAttrsToList (
        key: value:
        let
          json = pkgs.writeText "voiceink-${key}.json" (builtins.toJSON value);
        in
        ''
          /usr/bin/defaults write ${lib.escapeShellArg domain} ${lib.escapeShellArg key} -data "$(/usr/bin/xxd -p ${json} | /usr/bin/tr -d '\n')"
        ''
      ) settings.jsonData
    )
  );
in
{
  system.defaults.CustomUserPreferences.${domain} = settings.preferences;

  system.activationScripts.postActivation.text = lib.mkBefore ''
    sudo -u ${lib.escapeShellArg username} ${applyData}
  '';
}
