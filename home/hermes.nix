{
  inputs,
  pkgs,
  lib,
  hostConfig,
  ...
}:
lib.mkIf hostConfig.isLinux {
  home.packages = [
    inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
