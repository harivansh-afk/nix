{
  config,
  lib,
  pkgs,
  ...
}:
let
  sourceFile = ../config/devin/config.json;
  targetDir = "${config.xdg.configHome}/devin";
  targetFile = "${targetDir}/config.json";
  bin = "${pkgs.coreutils}/bin";
in
{
  # Devin rewrites this file when settings change, so seed a mutable copy
  # instead of pointing the path at the read-only Nix store.
  home.activation.installDevinConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${bin}/mkdir -p "${targetDir}"

    if [ -f "${targetFile}" ] && ! ${bin}/cmp -s "${sourceFile}" "${targetFile}"; then
      timestamp="$(${bin}/date +%Y%m%d%H%M%S)"
      ${bin}/cp "${targetFile}" "${targetFile}.hm-bak.$timestamp"
    fi

    ${bin}/install -m 600 "${sourceFile}" "${targetFile}"
  '';
}
