{
  config,
  pkgs,
  username,
  ...
}:
let
  authorizedKeys = [
    # ~/.ssh/id_ed25519.pub on macbook (rathi@mac)
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM6tzq33IQcurWoQ7vhXOTLjv8YkdTGb7NoNsul3Sbfu rathi@mac"
  ];
  passwordHashFile = config.sops.secrets."user-password-hash".path;
in
{
  # Console/login password hash for rathi + root. `neededForUsers`
  # deposits the file under /run/secrets-for-users/ before user
  # activation runs, which is required when mutableUsers = false.
  sops.secrets."user-password-hash" = {
    sopsFile = ../../secrets/spark/user-password-hash;
    format = "binary";
    neededForUsers = true;
  };

  sops.secrets."mgrep.env" = {
    sopsFile = ../../secrets/spark/mgrep.env;
    format = "binary";
    owner = username;
    mode = "0400";
  };

  sops.secrets."linear.env" = {
    sopsFile = ../../secrets/spark/linear.env;
    format = "binary";
    owner = username;
    mode = "0400";
  };

  users.mutableUsers = false;

  users.users.${username} = {
    isNormalUser = true;
    description = "rathi";
    shell = pkgs.zsh;
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "podman"
    ];
    openssh.authorizedKeys.keys = authorizedKeys;
    hashedPasswordFile = passwordHashFile;
  };

  # Keep root reachable during bootstrap; tighten to `prohibit-password`
  # only (set below in services.openssh) so passwords still can't be used.
  users.users.root.openssh.authorizedKeys.keys = authorizedKeys;
  users.users.root.hashedPasswordFile = passwordHashFile;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  # wheel members can sudo without a password — fine for a single-user
  # box where login is already gated by SSH keys.
  security.sudo.wheelNeedsPassword = false;
}
