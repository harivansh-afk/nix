{
  inputs,
  lib,
  ...
}:
{
  perSystem =
    { pkgs, system, ... }:
    {
      formatter = pkgs.nixfmt-tree;

      packages = {
        inherit (inputs.home-manager.packages.${system}) home-manager;
        inherit (inputs.nixos-anywhere.packages.${system}) nixos-anywhere;
      }
      // lib.optionalAttrs (lib.hasSuffix "darwin" system) {
        inherit (inputs.nix-darwin.packages.${system}) darwin-rebuild;
      };

      devShells.default = pkgs.mkShell {
        packages = with pkgs; [
          deadnix
          git
          just
          nixfmt-tree
          nh
          prettier
          pre-commit
          selene
          shfmt
          statix
          stylua
        ];
      };
    };
}
