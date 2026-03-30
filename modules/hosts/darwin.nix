{
  hosts,
  inputs,
  username,
  mkSpecialArgs,
  mkHomeManagerModule,
  ...
}:
let
  host = hosts.darwin;
in
{
  flake.darwinConfigurations.${host.name} = inputs.nix-darwin.lib.darwinSystem {
    system = host.system;
    specialArgs = mkSpecialArgs host;
    modules = [
      ../../hosts/${host.name}
      inputs.home-manager.darwinModules.home-manager
      inputs.nix-homebrew.darwinModules.nix-homebrew
      {
        users.users.${username}.home = host.homeDirectory;

        nix-homebrew = {
          enable = true;
          enableRosetta = true;
          user = username;
          autoMigrate = true;
        };
      }
      (mkHomeManagerModule host)
    ];
  };
}
