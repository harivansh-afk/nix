# The host registry. Two machines do not need a typed inventory layer:
# each record carries the facts the flake wiring consumes (kind, system,
# username) plus the values derived from them. Everything else about a
# host lives in hosts/<name>/.
{
  self,
  inputs,
  lib,
  ...
}:
let
  mkHost =
    name:
    {
      kind,
      system,
      username,
    }:
    let
      isDarwin = kind == "darwin";
    in
    {
      inherit
        isDarwin
        kind
        name
        system
        username
        ;
      hostname = name;
      isLinux = !isDarwin;
      homeDirectory = if isDarwin then "/Users/${username}" else "/home/${username}";
    };

  hosts = lib.mapAttrs mkHost {
    macbook = {
      kind = "darwin";
      system = "aarch64-darwin";
      username = "rathi";
    };
    spark = {
      kind = "nixos";
      system = "aarch64-linux";
      username = "rathi";
    };
  };

  mkPkgs =
    system:
    import (if lib.hasSuffix "-darwin" system then inputs.nixpkgs-macbook else inputs.nixpkgs) {
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
