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
        {
          nixpkgs.overlays = [
            (final: _prev: {
              agent-browser = final.callPackage ../pkgs/agent-browser { src = inputs.agent-browser; };
            })
          ];
        }
        ../hosts/${host.name}
      ];
    };
in
{
  flake.nixosConfigurations = lib.mapAttrs (_: mkNixos) nixosHosts;
}
