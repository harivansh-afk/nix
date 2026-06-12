{
  hosts,
  inputs,
  lib,
  username,
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
          users.users.${username}.home = host.homeDirectory;

          nix-homebrew = {
            enable = true;
            enableRosetta = false;
            user = username;
            autoMigrate = true;
          };

          determinateNix = {
            enable = true;
            # Same attrset spark uses for nix.settings; Determinate owns
            # nix.conf on darwin, so it is fed in through customSettings.
            customSettings = import ../system/nix-settings.nix username;
          };
        }
      ];
    };
in
{
  flake.darwinConfigurations = lib.mapAttrs (_: mkDarwin) darwinHosts;
}
