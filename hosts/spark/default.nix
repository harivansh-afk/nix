{
  inputs,
  self,
  hostname,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    inputs.disko.nixosModules.disko
    inputs.dgx-spark.nixosModules.dgx-spark
    inputs.lanzaboote.nixosModules.lanzaboote
    ../../modules/common.nix
    inputs.sops-nix.nixosModules.sops
    ../../modules/security/sops.nix
    ../../modules/users/nixos.nix
    ./kernel-hardening.nix
    ./services/beeper-bridges.nix
    ./services/caddy.nix
    ./services/claude-proxy.nix
    ./services/desktop.nix
    ./services/cloudflared.nix
    ./services/sharefs.nix
    ./services/forgejo
    ./services/hermes
    ./services/roomcast.nix
    ./services/airplay-beacon.nix
    ./services/inference.nix
    ./services/mixbridge.nix
    ./services/draw.nix
    ./services/mosh.nix
    ./services/muxd.nix
    ./services/vaultwarden.nix
    ./services/website.nix
    ./hardware.nix
    ./networking.nix
    ./users.nix
  ]
  ++ lib.optional (builtins.pathExists ./hardware-configuration.nix) ./hardware-configuration.nix;

  networking.hostName = hostname;

  boot = {
    lanzaboote = {
      configurationLimit = 4;
      enable = true;
      pkiBundle = "/var/lib/sbctl";
    };
    loader.systemd-boot.editor = false;
  };

  security.tpm2.enable = true;

  nixpkgs.config.cudaCapabilities = [ "12.1" ];

  nix.settings = {
    accept-flake-config = true;
    experimental-features = [
      "fetch-tree"
    ];
  };

  environment.systemPackages = with pkgs; [
    clang
  ];

  programs.git = {
    enable = true;
    config = {
      http = {
        lowSpeedLimit = 1000;
        lowSpeedTime = 60;
      };
    };
  };

  programs.nh = {
    enable = true;
    clean = {
      enable = true;
      extraArgs = "--keep-since 7d --keep 5";
    };
  };

  system.configurationRevision = self.rev or self.dirtyRev or null;

  system.stateVersion = "25.11";

  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc.lib
      zlib
      openssl
      curl
      glib
      libgcc
    ];
  };
}
