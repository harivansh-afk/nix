{
  hosts,
  inputs,
  lib,
  mkSpecialArgs,
  ...
}:
let
  darwinHosts = lib.filterAttrs (_: host: host.kind == "darwin") hosts;

  mkDarwin =
    host:
    inputs.nix-darwin.lib.darwinSystem {
      specialArgs = mkSpecialArgs host;
      modules = [
        { nixpkgs.hostPlatform = host.system; }
        inputs.determinate.darwinModules.default
        ../hosts/${host.name}
        inputs.nix-homebrew.darwinModules.nix-homebrew
        {
          users.users.${host.username}.home = host.homeDirectory;

          nix-homebrew = {
            enable = true;
            enableRosetta = false;
            user = host.username;
            autoMigrate = true;
          };

          determinateNix = {
            enable = true;
            # Same attrset spark uses for nix.settings; Determinate owns
            # nix.conf on darwin, so it is fed in through customSettings.
            customSettings = import ../system/nix-settings.nix host.username;
          };
        }
      ];
    };
in
{
  flake.darwinConfigurations = lib.mapAttrs (_: mkDarwin) darwinHosts;
}
