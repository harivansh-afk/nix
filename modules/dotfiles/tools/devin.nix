{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  devinPackage = inputs.devin-cli.packages.${pkgs.stdenv.hostPlatform.system}.default;
  sourceFile = ../../../dots/devin/config.json;
  targetDir = "${config.xdg.configHome}/devin";
  targetFile = "${targetDir}/config.json";
  coreutilsBin = "${pkgs.coreutils}/bin";
  cmpBin = "${pkgs.diffutils}/bin/cmp";
in
{
  packages = [ devinPackage ];

  activationLines = ''
    ${coreutilsBin}/mkdir -p ${lib.escapeShellArg targetDir}

    if [ -f ${lib.escapeShellArg targetFile} ] && ! ${cmpBin} -s ${sourceFile} ${lib.escapeShellArg targetFile}; then
      timestamp="$(${coreutilsBin}/date +%Y%m%d%H%M%S)"
      ${coreutilsBin}/cp ${lib.escapeShellArg targetFile} ${lib.escapeShellArg "${targetFile}.bak."}$timestamp
    fi

    ${coreutilsBin}/install -m 600 ${sourceFile} ${lib.escapeShellArg targetFile}
  '';
}
