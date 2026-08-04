{
  inputs,
  self,
  ...
}:
{
  flake.nixosConfigurations.ix = inputs.nixpkgs.lib.nixosSystem {
    specialArgs = { inherit inputs self; };
    modules = [
      { nixpkgs.hostPlatform = "x86_64-linux"; }
      ../hosts/ix
    ];
  };
}
