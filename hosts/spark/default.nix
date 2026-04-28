{
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
    ../../modules/security/sops.nix
    ../../modules/services/caddy.nix
    ../../modules/services/cloudflared.nix
    ../../modules/services/delta.nix
    ../../modules/services/forgejo.nix
    ../../modules/services/vaultwarden.nix
    ./hardware.nix
    ./networking.nix
    ./users.nix
  ]
  ++ lib.optional (builtins.pathExists ./hardware-configuration.nix) ./hardware-configuration.nix;

  networking.hostName = hostname;

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
