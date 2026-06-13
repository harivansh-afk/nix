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
    inherit (pkgs) zsh;
    inherit (pkgs) bash;
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
        inherit (user) extraGroups;
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
