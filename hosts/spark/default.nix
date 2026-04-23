{
  self,
  hostname,
  lib,
  ...
}:
{
  imports = [
    ../../system/common.nix
    ../../system/packages.nix
    ./bootstrap.nix
    ./hardware.nix
    ./disk-config.nix
    ./networking.nix
    ./users.nix
    ./services.nix
  ]
  # `hardware-configuration.nix` is generated on-device by nixos-anywhere
  # (`--generate-hardware-config ...`) during the first install. Import it
  # only once it exists so eval works cleanly both before and after the
  # initial deploy.
  ++ lib.optional (builtins.pathExists ./hardware-configuration.nix)
    ./hardware-configuration.nix;

  networking.hostName = hostname;

  system.configurationRevision = self.rev or self.dirtyRev or null;

  # Matches the upstream dgx-spark nixos-anywhere template. Don't bump
  # without reading the NixOS release notes for stateful-data migrations.
  system.stateVersion = "25.11";
}
