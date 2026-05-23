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
  env = "${pkgs.coreutils}/bin/env";
  id = "${pkgs.coreutils}/bin/id";

  perUserActivation =
    name: userCfg:
    let
      script = pkgs.writeText "dotfiles-install-${name}.sh" (helpers.buildUserScript userCfg);
    in
    ''
      if id ${lib.escapeShellArg userCfg.username} >/dev/null 2>&1; then
        uid="$(${id} -u ${lib.escapeShellArg userCfg.username})"
        ${runuser} -u ${lib.escapeShellArg userCfg.username} -- ${env} \
          HOME=${lib.escapeShellArg userCfg.homeDirectory} \
          USER=${lib.escapeShellArg userCfg.username} \
          LOGNAME=${lib.escapeShellArg userCfg.username} \
          XDG_RUNTIME_DIR="/run/user/$uid" \
          ${bash} ${script}
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
      deps = [
        "users"
        "setupSecrets"
        "setupSecretsForUsers"
      ];
    };

    users.users = lib.mapAttrs (_: u: { packages = u.packages; }) enabledUsers;
  };
}
