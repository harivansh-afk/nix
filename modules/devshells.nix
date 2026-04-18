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

      packages =
        {
          home-manager = inputs.home-manager.packages.${system}.home-manager;
        }
        // lib.optionalAttrs (lib.hasSuffix "darwin" system) {
          darwin-rebuild = inputs.nix-darwin.packages.${system}.darwin-rebuild;
        };

      devShells.default = pkgs.mkShell {
        packages = with pkgs; [
          deadnix
          git
          just
          nixfmt-tree
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
