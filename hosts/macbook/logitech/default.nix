{
  lib,
  pkgs,
  username,
  ...
}:
{
  system.activationScripts.preActivation.text = lib.mkBefore ''
    sudo -u ${username} ${pkgs.python3}/bin/python3 ${./seed.py} \
      ${./.} "/Users/${username}/Library/Application Support/LogiOptionsPlus"
  '';
}
