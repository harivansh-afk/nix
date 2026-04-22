{
  self,
  hostname,
  ...
}:
{
  imports = [
    ../../system/common.nix
    ../../system/packages.nix
    ./hardware.nix
    ./disk-config.nix
    ./networking.nix
    ./users.nix
    ./services.nix
  ];

  networking.hostName = hostname;

  system.configurationRevision = self.rev or self.dirtyRev or null;

  # Matches the upstream dgx-spark nixos-anywhere template. Don't bump
  # without reading the NixOS release notes for stateful-data migrations.
  system.stateVersion = "25.11";
}
