{
  self,
  inputs,
  lib,
  ...
}:
let
  username = "rathi";
  hosts = import ../inventory { inherit lib username; };

  mkPkgs =
    system:
    import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };

  mkSpecialArgs = host: {
    inherit inputs self username;
    inherit (host) hostname;
    hostConfig = host;
  };

  mkHomeManagerModule = host: {
    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
    home-manager.extraSpecialArgs = mkSpecialArgs host;
    home-manager.backupCommand = "bash ${../scripts/lib/home-manager-backup.sh}";
    home-manager.users.${username} = import ../home;
  };
in
{
  systems = lib.unique (
    [
      "x86_64-linux"
    ]
    ++ map (host: host.system) (builtins.attrValues hosts)
  );

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
