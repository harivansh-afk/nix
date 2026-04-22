{
  pkgs,
  username,
  ...
}:
let
  authorizedKeys = [
    # ~/.ssh/id_ed25519.pub on macbook (rathi@mac)
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM6tzq33IQcurWoQ7vhXOTLjv8YkdTGb7NoNsul3Sbfu rathi@mac"
  ];
in
{
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
  };

  # Keep root reachable during bootstrap; tighten to `prohibit-password`
  # only (set below in services.openssh) so passwords still can't be used.
  users.users.root.openssh.authorizedKeys.keys = authorizedKeys;

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
