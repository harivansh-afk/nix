# nix-darwin adapter for modules/users/user-config.nix: the primary user
# gets the shared user config, applied as a postActivation step running as
# that user. Symlinks point at the live checkout so dotfile edits apply
# without a rebuild.
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
  # nix-darwin has no per-user package sets; these are the old
  # home-manager-installed user packages.
  environment.systemPackages = userConfig.packages;

  system.activationScripts.postActivation.text = lib.mkAfter ''
    echo "applying user config for ${username}..."
    sudo -u ${username} ${userConfig.script} \
      || echo "warning: user config for ${username} failed" >&2
  '';
}
