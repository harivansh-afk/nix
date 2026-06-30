{
  lib,
  pkgs,
  hostname,
  username,
  ...
}:
let
  userConfig = import ./user-config.nix {
    inherit lib pkgs hostname;
    isDarwin = true;
    user = {
      name = username;
      homeDirectory = "/Users/${username}";
    };
    dotsRoot = "/Users/${username}/Documents/Git/nix/dots";
  };
in
{
  environment.systemPackages = userConfig.packages;

  system.activationScripts.postActivation.text = lib.mkAfter ''
    echo "applying user config for ${username}..."
    sudo -u ${username} ${userConfig.script} \
      || echo "warning: user config for ${username} failed" >&2
  '';
}
