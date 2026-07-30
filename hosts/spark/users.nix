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
      root.hashedPassword = "!";
    };

  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      AllowAgentForwarding = false;
      AllowTcpForwarding = false;
      AllowUsers = enabledUsers;
      AuthenticationMethods = "publickey";
      GatewayPorts = "no";
      KbdInteractiveAuthentication = false;
      MaxAuthTries = 3;
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      PermitTunnel = false;
      X11Forwarding = false;
    };
  };

  security.sudo.wheelNeedsPassword = true;
}
