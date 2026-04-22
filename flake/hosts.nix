{
  hosts,
  inputs,
  username,
  mkSpecialArgs,
  mkHomeManagerModule,
  ...
}:
let
  host = hosts.macbook;
in
{
  flake.darwinConfigurations.${host.name} = inputs.nix-darwin.lib.darwinSystem {
    system = host.system;
    specialArgs = mkSpecialArgs host;
    modules = [
      inputs.determinate.darwinModules.default
      ../hosts/macbook
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

        # The determinate nix-darwin module force-disables `nix.*` and
        # writes its own settings to /etc/nix/nix.custom.conf. Mirror the
        # baseline from system/common.nix here. GC, daemon, and the nix
        # package itself are all managed by determinate-nixd.
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
}
