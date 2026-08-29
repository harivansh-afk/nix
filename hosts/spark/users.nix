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

  # Forgejo serves git over this sshd as the `git` user, which is not an
  # account here, so AllowUsers must admit it explicitly; source-qualified so
  # it can only authenticate from loopback or the tailnet.
  gitSshOrigins = [
    "git@127.0.0.1"
    "git@::1"
    "git@100.64.0.0/10" # tailscale IPv4 (CGNAT)
    "git@fd7a:115c:a1e0::/48" # tailscale IPv6 (ULA)
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
      AllowTcpForwarding = true;
      AllowUsers = enabledUsers ++ lib.optionals config.services.forgejo.enable gitSshOrigins;
      AuthenticationMethods = "publickey";
      GatewayPorts = "no";
      KbdInteractiveAuthentication = false;
      MaxAuthTries = 3;
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      PermitTunnel = false;
      X11Forwarding = false;
    };

    # Forgejo's forced `forgejo serv` command already limits the git user;
    # this removes tty and forwarding underneath it. extraConfig lands at the
    # end of sshd_config, the only place a Match block may go.
    extraConfig = lib.optionalString config.services.forgejo.enable ''
      Match User git
        PermitTTY no
        AllowAgentForwarding no
        AllowTcpForwarding no
        PermitTunnel no
        X11Forwarding no
    '';
  };

  security.sudo.wheelNeedsPassword = true;
}
