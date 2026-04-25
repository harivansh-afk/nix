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
  # `hardware-configuration.nix` is generated on-device by nixos-anywhere
  # (`--generate-hardware-config ...`) during the first install. Import it
  # only once it exists so eval works cleanly both before and after the
  # initial deploy.
  ++ lib.optional (builtins.pathExists ./hardware-configuration.nix) ./hardware-configuration.nix;

  networking.hostName = hostname;

  environment.systemPackages = with pkgs; [
    clang
  ];

  system.configurationRevision = self.rev or self.dirtyRev or null;

  # Matches the upstream dgx-spark nixos-anywhere template. Don't bump
  # without reading the NixOS release notes for stateful-data migrations.
  system.stateVersion = "25.11";

  # cursor-agent / claude / codex are all distributed as curl|bash'd,
  # dynamically-linked glibc binaries expecting an FHS loader at
  # /lib64/ld-linux-*.so.2. nix-ld installs a stub loader + a small set of
  # common libraries at the standard paths so these just work on NixOS.
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
