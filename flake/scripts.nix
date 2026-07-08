{ lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      inherit (import ../scripts/portable.nix { inherit lib pkgs; }) packages;
    };
}
