{
  inputs,
  lib,
  modulesPath,
  pkgs,
  username,
  self,
  ...
}:
let
  packageSets = import ../../lib/package-sets.nix { inherit inputs lib pkgs; };
in
{
  imports = [
    ./hardware-configuration.nix
    ./disk-config.nix
    ../../modules/base.nix
    (modulesPath + "/profiles/minimal.nix")
    (modulesPath + "/profiles/headless.nix")
  ];

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    device = "nodev";
    configurationLimit = 3;
  };

  documentation.enable = false;
  fonts.fontconfig.enable = false;

  networking = {
    hostName = "netty";
    useDHCP = false;
    interfaces.ens3 = {
      ipv4.addresses = [
        {
          address = "152.53.195.59";
          prefixLength = 22;
        }
      ];
    };
    defaultGateway = {
      address = "152.53.192.1";
      interface = "ens3";
    };
    nameservers = [
      "1.1.1.1"
      "8.8.8.8"
    ];
    firewall.allowedTCPPorts = [
      22
      80
      443
    ];
  };

  services.qemuGuest.enable = true;

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  # Emergency console access - generate hashed password and save to Bitwarden later
  users.users.root = {
    initialPassword = "temppass123";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM6tzq33IQcurWoQ7vhXOTLjv8YkdTGb7NoNsul3Sbfu rathi@mac"
    ];
  };

  users.users.${username} = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
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

  nix.gc.options = lib.mkForce "--delete-older-than 3d";

  nix.extraOptions = ''
    min-free = ${toString (100 * 1024 * 1024)}
    max-free = ${toString (1024 * 1024 * 1024)}
  '';

  services.journald.extraConfig = "MaxRetainedFileSec=1week";

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
