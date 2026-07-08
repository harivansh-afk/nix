{
  self,
  inputs,
  lib,
  ...
}:
let
  hosts = import ../inventory { inherit lib; };

  mkPkgs =
    system:
    import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };

  mkSpecialArgs = host: {
    inherit inputs self;
    inherit (host) hostname username;
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
      hosts
      mkPkgs
      mkSpecialArgs
      ;
  };
}
