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
  ];

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    device = "nodev";
    configurationLimit = 5;
  };

  networking = {
    hostName = "rathi-vps";
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

  programs.zsh.enable = true;
  environment.shells = [pkgs.zsh];

  environment.variables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };

  nix.settings = {
    auto-optimise-store = true;
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [
      "root"
      username
    ];
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = packageSets.core ++ packageSets.extras;

  system.configurationRevision = self.rev or self.dirtyRev or null;
  system.stateVersion = "24.11";
}
