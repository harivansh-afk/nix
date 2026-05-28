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
    ../../system/common.nix
    ../../system/packages.nix
    inputs.sops-nix.nixosModules.sops
    ../../modules/security/sops.nix
    ../../modules/security/user-isolation.nix
    ../../modules/services/caddy.nix
    ../../modules/services/cloudflared.nix
    ../../modules/services/delta.nix
    ../../modules/services/forgejo
    ../../modules/services/inference.nix
    ../../modules/services/mosh.nix
    ../../modules/services/playbook.nix
    ../../modules/services/vaultwarden.nix
    ../../modules/services/website.nix
    ./hardware.nix
    ./networking.nix
    ./pi.nix
    ./barrett/system.nix
    ./users.nix
  ]
  ++ lib.optional (builtins.pathExists ./hardware-configuration.nix) ./hardware-configuration.nix;

  networking.hostName = hostname;

  nixpkgs.config.cudaCapabilities = [ "12.1" ];

  environment.systemPackages = with pkgs; [
    clang
  ];

  system.configurationRevision = self.rev or self.dirtyRev or null;

  boot.specialFileSystems."/proc".options = [ "hidepid=invisible" ];

  boot.kernel.sysctl = {
    "kernel.yama.ptrace_scope" = 2;
    "kernel.dmesg_restrict" = 1;
    "kernel.kptr_restrict" = 2;
  };

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
