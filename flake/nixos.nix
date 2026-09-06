{
  hosts,
  inputs,
  lib,
  mkSpecialArgs,
  self,
  ...
}:
let
  nixosHosts = lib.filterAttrs (_: host: host.kind == "nixos") hosts;

  mkNixos =
    host:
    inputs.nixpkgs.lib.nixosSystem {
      specialArgs = mkSpecialArgs host;
      modules = [
        { nixpkgs.hostPlatform = host.system; }
        ../hosts/${host.name}
      ];
    };

  # Root-only container image, not a host in lib/hosts.nix.
  ix = inputs.nixpkgs.lib.nixosSystem {
    specialArgs = { inherit inputs self; };
    modules = [
      { nixpkgs.hostPlatform = "x86_64-linux"; }
      ../hosts/ix
    ];
  };
in
{
  flake.nixosConfigurations = lib.mapAttrs (_: mkNixos) nixosHosts // {
    inherit ix;
  };
  flake.checks.${hosts.spark.system}.photon-replies =
    self.nixosConfigurations.spark.config.services.hermes-agent.package.tests.photon-replies;
}
