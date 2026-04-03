{
  hosts,
  inputs,
  mkSpecialArgs,
  mkHomeManagerModule,
  ...
}:
let
  host = hosts.netty;
in
{
  flake = {
    nixosConfigurations.${host.name} = inputs.nixpkgs.lib.nixosSystem {
      system = host.system;
      specialArgs = mkSpecialArgs host;
      modules = [
        inputs.disko.nixosModules.disko
        inputs.openClaw.nixosModules.openclaw-gateway
        ../../hosts/${host.name}/configuration.nix
        inputs.home-manager.nixosModules.home-manager
        (mkHomeManagerModule host)
      ];
    };
  };
}
