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
