{
  lib,
  pkgs,
  ...
}:
let
  spaces = pkgs.callPackage ../../pkgs/cua-spaces { };
in
{
  environment.systemPackages = [ (pkgs.callPackage ../../pkgs/com-computer { }) ];

  system.activationScripts.postActivation.text = lib.mkAfter ''
    /usr/bin/ditto "${spaces}/Applications/Cua Spaces.app" "/Applications/Cua Spaces.app"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/Cua Spaces.app"
  '';
}
