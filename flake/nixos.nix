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
      ../hosts/spark
    ];
  };
}
