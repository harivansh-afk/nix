{
  hosts,
  inputs,
  lib,
  mkSpecialArgs,
  ...
}:
let
  nixosHosts = lib.filterAttrs (_: host: host.kind == "nixos") hosts;

  mkNixos =
    host:
    inputs.nixpkgs.lib.nixosSystem {
      specialArgs = mkSpecialArgs host;
      modules = [
        { nixpkgs.hostPlatform = host.system; }
        ../hosts/${host.name}
      ];
    };
in
{
  flake.nixosConfigurations = lib.mapAttrs (_: mkNixos) nixosHosts;
}
