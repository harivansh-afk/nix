{
  inputs,
  lib,
  pkgs,
  username,
  self,
  ...
}: let
  packageSets = import ../../lib/package-sets.nix {inherit inputs lib pkgs;};
in {
  imports = [
    ./hardware-configuration.nix
    ./disk-config.nix
    ../../modules/base.nix
  ];

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    device = "nodev";
    configurationLimit = 5;
  };

  networking = {
    hostName = "netty";
    useDHCP = true;
    firewall.allowedTCPPorts = [22 80 443];
  };

  services.qemuGuest.enable = true;

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM6tzq33IQcurWoQ7vhXOTLjv8YkdTGb7NoNsul3Sbfu rathi@mac"
  ];

  users.users.${username} = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM6tzq33IQcurWoQ7vhXOTLjv8YkdTGb7NoNsul3Sbfu rathi@mac"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  nix.settings.trusted-users = lib.mkForce [
    "root"
    username
  ];

  environment.systemPackages = packageSets.extras ++ [
    pkgs.bubblewrap
    pkgs.pnpm
  ];

  systemd.tmpfiles.rules = [
    "L /usr/bin/bwrap - - - - ${pkgs.bubblewrap}/bin/bwrap"
  ];

  system.configurationRevision = self.rev or self.dirtyRev or null;
  system.stateVersion = "24.11";
}
