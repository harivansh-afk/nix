{
  config,
  lib,
  mkSparkSecret,
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
  sops.secrets."user-password-hash" = mkSparkSecret "user-password-hash" {
    neededForUsers = true;
  };

  sops.secrets."mgrep.env" = mkSparkSecret "mgrep.env" {
    owner = username;
    mode = "0400";
  };

  sops.secrets."linear.env" = mkSparkSecret "linear.env" {
    owner = username;
    mode = "0400";
  };

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
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  security.sudo.wheelNeedsPassword = false;
}
