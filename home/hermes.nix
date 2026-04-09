{
  inputs,
  pkgs,
  hostConfig,
  lib,
  ...
}:
lib.mkIf hostConfig.isLinux {
  home.packages = [
    inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
