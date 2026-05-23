{
  config,
  lib,
  pkgs,
  ...
}:
let
  helpers = import ../lib.nix { inherit pkgs lib; };
  enabledUsers = lib.filterAttrs (_: u: u.enable) config.dotfiles.users;

  perUserActivation =
    name: userCfg:
    let
      script = pkgs.writeText "dotfiles-install-${name}.sh" (helpers.buildUserScript userCfg);
    in
    ''
      if id ${lib.escapeShellArg userCfg.username} >/dev/null 2>&1; then
        /usr/bin/sudo -u ${lib.escapeShellArg userCfg.username} /usr/bin/env \
          HOME=${lib.escapeShellArg userCfg.homeDirectory} \
          USER=${lib.escapeShellArg userCfg.username} \
          LOGNAME=${lib.escapeShellArg userCfg.username} \
          ${pkgs.bash}/bin/bash ${script}
      else
        echo "dotfiles: user ${userCfg.username} does not exist, skipping" >&2
      fi
    '';

  combinedActivation = lib.concatStringsSep "\n" (lib.mapAttrsToList perUserActivation enabledUsers);

  allPackages = lib.flatten (lib.mapAttrsToList (_: u: u.packages) enabledUsers);
in
{
  config = lib.mkIf (enabledUsers != { }) {
    system.activationScripts.postActivation.text = lib.mkAfter ''
      echo "dotfiles: installing per-user state..."
      ${combinedActivation}
    '';

    environment.systemPackages = allPackages;
  };
}
