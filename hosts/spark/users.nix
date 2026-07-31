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

  # Forgejo serves git over SSH as the `git` service user, through this sshd
  # (it runs no SSH server of its own). `git` is not in users/, so it is not
  # in enabledUsers, and AllowUsers refuses it before a key is ever read:
  # "User git from ::1 not allowed because not listed in AllowUsers". That is
  # what broke every ssh push to git.harivan.sh from spark itself.
  #
  # Source-qualified rather than added flat. AllowUsers takes user@host
  # patterns with CIDR masks, so the git user may authenticate ONLY from
  # loopback or the tailnet - the same boundary the closed firewall draws for
  # humans, asserted a second time in sshd instead of trusted to the firewall
  # alone. A git.harivan.sh that ever stopped being Cloudflare-fronted still
  # could not turn into an ssh entry point.
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
      AllowTcpForwarding = false;
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

    # Behind Forgejo's own defence: it writes authorized_keys entries with a
    # forced `forgejo serv` command, so the git user cannot ask for anything
    # else. This is the layer under that - even if the forced command were
    # bypassed, the account gets no tty and no forwarding of any kind.
    #
    # extraConfig is concatenated onto the END of sshd_config (see the
    # `sshconf` derivation in nixos/modules/services/networking/ssh/sshd.nix),
    # which is the only place a Match block may go: everything after one
    # belongs to it.
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
