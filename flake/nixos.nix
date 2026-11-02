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
          # Packages from private flake inputs that plain `pkgs` consumers need. NixOS builds
          # its own pkgs, so the overlay in flake/args.nix does not reach host modules.
          nixpkgs.overlays = [
            (_final: _prev: {
              browser-dom-use = inputs.browser-dom-use.packages.${host.system}.default;
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
