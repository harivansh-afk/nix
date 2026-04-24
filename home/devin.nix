{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  devinPackage = inputs.devin-cli.packages.${pkgs.stdenv.hostPlatform.system}.default;
  sourceFile = ../dots/devin/config.json;
  targetDir = "${config.xdg.configHome}/devin";
  targetFile = "${targetDir}/config.json";
  coreutilsBin = "${pkgs.coreutils}/bin";
  cmpBin = "${pkgs.diffutils}/bin/cmp";
in
{
  home.packages = [ devinPackage ];

  # Devin rewrites this file when settings change, so seed a mutable copy
  # instead of pointing the path at the read-only Nix store.
  home.activation.installDevinConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${coreutilsBin}/mkdir -p "${targetDir}"

    if [ -f "${targetFile}" ] && ! ${cmpBin} -s "${sourceFile}" "${targetFile}"; then
      timestamp="$(${coreutilsBin}/date +%Y%m%d%H%M%S)"
      ${coreutilsBin}/cp "${targetFile}" "${targetFile}.hm-bak.$timestamp"
    fi

    ${coreutilsBin}/install -m 600 "${sourceFile}" "${targetFile}"
  '';
}
