{
  hosts,
  inputs,
  mkSpecialArgs,
  ...
}:
let
  host = hosts.spark;
in
{
  flake.nixosConfigurations.${host.name} = inputs.nixpkgs.lib.nixosSystem {
    specialArgs = mkSpecialArgs host;
    modules = [
      { nixpkgs.hostPlatform = host.system; }
      inputs.disko.nixosModules.disko
      inputs.dgx-spark.nixosModules.dgx-spark
      inputs.home-manager.nixosModules.home-manager
      ../hosts/spark
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.extraSpecialArgs = mkSpecialArgs host;
        home-manager.backupCommand = "bash ${../scripts/lib/home-manager-backup.sh}";
      }
    ];
  };
}
