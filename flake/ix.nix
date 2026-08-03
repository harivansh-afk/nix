{
  inputs,
  self,
  ...
}:
let
  module =
    { pkgs, ... }:
    {
      imports = [ ../hosts/ix ];

      environment.systemPackages = [
        self.packages.${pkgs.stdenv.hostPlatform.system}.omp
        inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default
      ];
    };
  vm = inputs.index.lib.mkDev {
    inherit module;
    src = self;
  };
in
{
  flake.ix.default = vm.nixosConfigurations.dev;
}
