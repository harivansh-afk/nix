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
        inputs.determinate.nixosModules.default
        inputs.disko.nixosModules.disko
        inputs.hermes-agent.nixosModules.default
        ../hosts/netty/configuration.nix
        inputs.home-manager.nixosModules.home-manager
        (mkHomeManagerModule host)
      ];
    };
  };
}
