{ lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      packages = (import ../scripts/portable.nix { inherit lib pkgs; }).packages;
    };
}
