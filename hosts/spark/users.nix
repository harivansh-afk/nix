{
  config,
  lib,
  pkgs,
  username,
  ...
}:
let
  allUsers = import ../../modules/users/accounts;
  enabledUsers = builtins.attrNames allUsers;
  passwordHashFile = config.sops.secrets."user-password-hash".path;

  shellPackages = {
    inherit (pkgs) zsh;
    inherit (pkgs) bash;
  };

  gitSshOrigins = [
    "git@127.0.0.1"
    "git@::1"
    "git@100.64.0.0/10"
    "git@fd7a:115c:a1e0::/48"
  ];
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
      }
      // lib.optionalAttrs (user ? linger) {
        inherit (user) linger;
      }
      // lib.optionalAttrs (name == username) {
        uid = 1000;
        description = username;
        hashedPasswordFile = passwordHashFile;
      }
    )
    // {
      root.hashedPassword = "!";
    };

  programs.ssh.knownHosts.macbook = {
    hostNames = [
      "macbook"
      "macbook.taileb8b41.ts.net"
    ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINrnPjchazeyNUezSpyXgpsfo3F/01aajNtzlDSq9aHJ";
  };

  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      AllowAgentForwarding = false;
      AllowUsers = enabledUsers ++ lib.optionals config.services.forgejo.enable gitSshOrigins;
      AuthenticationMethods = "publickey";
      KbdInteractiveAuthentication = false;
      MaxAuthTries = 3;
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };

    extraConfig = lib.optionalString config.services.forgejo.enable ''
      Match User git
        PermitTTY no
        AllowAgentForwarding no
        AllowTcpForwarding no
        PermitTunnel no
        X11Forwarding no
    '';
  };
}
