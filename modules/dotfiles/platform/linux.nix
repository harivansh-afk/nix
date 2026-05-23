{
  config,
  lib,
  pkgs,
  ...
}:
let
  helpers = import ../lib.nix { inherit pkgs lib; };
  enabledUsers = lib.filterAttrs (_: u: u.enable) config.dotfiles.users;
  runuser = "${pkgs.util-linux}/bin/runuser";
  bash = "${pkgs.bash}/bin/bash";

  perUserActivation =
    name: userCfg:
    let
      script = pkgs.writeText "dotfiles-install-${name}.sh" (helpers.buildUserScript userCfg);
    in
    ''
      if id ${lib.escapeShellArg userCfg.username} >/dev/null 2>&1; then
        ${runuser} -u ${lib.escapeShellArg userCfg.username} -- ${bash} ${script}
      else
        echo "dotfiles: user ${userCfg.username} does not exist yet, skipping" >&2
      fi
    '';

  combinedActivation = lib.concatStringsSep "\n" (lib.mapAttrsToList perUserActivation enabledUsers);
in
{
  config = lib.mkIf (enabledUsers != { }) {
    system.activationScripts.dotfiles = {
      text = ''
        echo "dotfiles: installing per-user state..."
        ${combinedActivation}
      '';
      deps = [ "users" ];
    };

    # Per-user packages go to users.users.<name>.packages so each user gets
    # their own profile rather than polluting environment.systemPackages.
    users.users = lib.mapAttrs (_: u: { packages = u.packages; }) enabledUsers;
  };
}
