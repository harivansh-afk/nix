# NixOS adapter for modules/users/user-config.nix: every user in users/
# gets the shared user config, applied by a script that runs as that user
# during system activation.
#
# The repo owner's symlinks point at the live checkout
# (~/Documents/Git/nix/dots) so dotfile edits apply without a rebuild.
# Other users cannot read that checkout (homeMode 0700), so their links
# point at the nix-store copy of dots/ and update on rebuild.
{
  lib,
  pkgs,
  hostname,
  username,
  ...
}:
let
  allUsers = import ../../users;
  enabledUsers = builtins.attrNames allUsers;
  storeDots = "${../../dots}";

  mkUserConfig =
    name:
    import ./user-config.nix {
      inherit lib pkgs hostname;
      isDarwin = false;
      user = {
        inherit name;
        homeDirectory = "/home/${name}";
      };
      dotsRoot = if name == username then "/home/${name}/Documents/Git/nix/dots" else storeDots;
    };

  userConfigs = lib.genAttrs enabledUsers mkUserConfig;
in
{
  users.users = lib.mapAttrs (_: cfg: { inherit (cfg) packages; }) userConfigs;

  system.activationScripts = lib.mapAttrs' (
    name: cfg:
    lib.nameValuePair "userConfig-${name}" {
      deps = [
        "users"
        "groups"
      ];
      text = ''
        ${pkgs.util-linux}/bin/runuser -u ${name} -- ${cfg.script} \
          || echo "warning: user config for ${name} failed" >&2
      '';
    }
  ) userConfigs;
}
