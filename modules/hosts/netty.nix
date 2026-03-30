{
  hosts,
  inputs,
  mkPkgs,
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
        ../../hosts/${host.name}/configuration.nix
        inputs.home-manager.nixosModules.home-manager
        (mkHomeManagerModule host)
      ];
    };

    homeConfigurations.${host.name} = inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = mkPkgs host.system;
      extraSpecialArgs = mkSpecialArgs host;
      modules = [
        host.standaloneHomeModule
      ];
    };
  };
}
