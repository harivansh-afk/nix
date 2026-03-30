{
  self,
  inputs,
  lib,
  ...
}:
let
  username = "rathi";
  hosts = import ../lib/hosts.nix { inherit username; };

  mkPkgs =
    system:
    import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };

  mkSpecialArgs = host: {
    inherit inputs self username;
    hostname = host.hostname;
  };

  mkHomeManagerModule = host: {
    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
    home-manager.extraSpecialArgs = mkSpecialArgs host;
    home-manager.backupCommand = "bash ${../scripts/home-manager-backup.sh}";
    home-manager.users.${username} = import host.homeModule;
  };
in
{
  systems = lib.unique (map (host: host.system) (builtins.attrValues hosts));

  _module.args = {
    inherit
      username
      hosts
      mkPkgs
      mkSpecialArgs
      mkHomeManagerModule
      ;
  };
}
