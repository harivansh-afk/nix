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
    ./nginx.nix
    ./vaultwarden.nix
    ./forgejo.nix
    ./diffkit.nix
    ./betternas.nix
    ./hermes-gateway.nix
    ./forgejo-runner.nix
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

  users.users.root = {
    hashedPassword = "$6$T3d8stz8lq3N./Q/$QFDRHskykhr.SFozDTfX0ziisfz7ofRfyV/0tfCsBAxrZteJFj4sPTohmAiN3bOZOSVNkmaOD61vTFCMyuQ.S1";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFbL9gJC0IPX6XUdJSWBovp+zmHvooMmvl91QG3lllwN rathiharivansh@gmail.com"
    ];
  };

  users.users.${username} = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "docker"
    ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFbL9gJC0IPX6XUdJSWBovp+zmHvooMmvl91QG3lllwN rathiharivansh@gmail.com"
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

  # Provide /lib64/ld-linux-x86-64.so.2 so unpatched binaries
  # from npm, cargo-install, etc. can run without patchelf.
  programs.nix-ld.enable = true;

  virtualisation.docker.enable = true;

  environment.systemPackages = packageSets.extras ++ [
    pkgs.chromium
    pkgs.php
  ];

  system.configurationRevision = self.rev or self.dirtyRev or null;
  system.stateVersion = "24.11";
}
