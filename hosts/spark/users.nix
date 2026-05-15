{
  config,
  lib,
  pkgs,
  username,
  ...
}:
let
  allUsers = import ../../users;
  enabledUsers = builtins.attrNames allUsers;
  passwordHashFile = config.sops.secrets."user-password-hash".path;

  shellPackages = {
    zsh = pkgs.zsh;
    bash = pkgs.bash;
  };
in
{
  users.mutableUsers = false;

  users.users =
    lib.genAttrs enabledUsers (
      name:
      let
        user = allUsers.${name};
      in
      {
        isNormalUser = true;
        shell = shellPackages.${user.shell};
        extraGroups = user.extraGroups;
        openssh.authorizedKeys.keys = user.sshKeys;
        homeMode = "0700";
      }
      // lib.optionalAttrs (user ? linger) {
        inherit (user) linger;
      }
      // lib.optionalAttrs (name == username) {
        description = username;
        hashedPasswordFile = passwordHashFile;
      }
    )
    // {
      root = {
        openssh.authorizedKeys.keys = allUsers.${username}.sshKeys;
        hashedPasswordFile = passwordHashFile;
      };
    };

  home-manager.users = lib.genAttrs enabledUsers (name: import ./${name});

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  security.sudo.wheelNeedsPassword = false;
}
