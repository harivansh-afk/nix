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
      ;
  };
}
