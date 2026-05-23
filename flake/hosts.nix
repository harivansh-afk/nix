{
  hosts,
  inputs,
  username,
  mkSpecialArgs,
  ...
}:
let
  host = hosts.macbook;
in
{
  flake.darwinConfigurations.${host.name} = inputs.nix-darwin.lib.darwinSystem {
    specialArgs = mkSpecialArgs host;
    modules = [
      { nixpkgs.hostPlatform = host.system; }
      inputs.determinate.darwinModules.default
      ../hosts/macbook
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
    ];
  };
}
