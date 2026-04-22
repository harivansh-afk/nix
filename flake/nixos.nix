{
  hosts,
  inputs,
  username,
  mkSpecialArgs,
  mkHomeManagerModule,
  ...
}:
let
  host = hosts.spark;
in
{
  flake.nixosConfigurations.${host.name} = inputs.nixpkgs.lib.nixosSystem {
    system = host.system;
    specialArgs = mkSpecialArgs host;
    modules = [
      inputs.disko.nixosModules.disko
      inputs.dgx-spark.nixosModules.dgx-spark
      inputs.home-manager.nixosModules.home-manager
      ../hosts/spark
      {
        users.users.${username}.home = host.homeDirectory;
      }
      (mkHomeManagerModule host)
    ];
  };
}
