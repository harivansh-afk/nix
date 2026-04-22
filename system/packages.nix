{
  inputs,
  lib,
  pkgs,
  hostConfig,
  ...
}:
let
  packageSets = import ../packages.nix { inherit inputs lib pkgs; };
in
{
  # `extras` is the kitchen-sink dev toolchain (awscli, gcloud, terraform,
  # texliveFull, phpPackages.composer, llmfit, ...). Most of it is only
  # wanted on the daily-driver laptop. Keep it off spark so rebuilds stay
  # fast and we don't hit aarch64-linux build breakage for things we
  # never actually use on the workstation.
  environment.systemPackages = lib.optionals hostConfig.isDarwin packageSets.extras;

  fonts.packages = packageSets.fonts;
}
