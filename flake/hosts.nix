{
  hosts,
  inputs,
  lib,
  username,
  mkSpecialArgs,
  mkHomeManagerModule,
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
        inputs.home-manager.darwinModules.home-manager
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
            customSettings = {
              auto-optimise-store = true;
              experimental-features = [
                "nix-command"
                "flakes"
              ];
              use-xdg-base-directories = true;
              max-jobs = "auto";
              cores = 0;
              trusted-users = [
                "root"
                username
              ];
            };
          };
        }
        (mkHomeManagerModule host)
      ];
    };
in
{
  flake.darwinConfigurations = lib.mapAttrs (_: mkDarwin) darwinHosts;
}
