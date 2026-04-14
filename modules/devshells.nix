{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      formatter = pkgs.nixfmt-tree;

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
