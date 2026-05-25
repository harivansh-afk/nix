{
  pkgs,
  sourceRoot,
}:
let
  forgejoRoot = sourceRoot + "/modules/services/forgejo";
  frontend = pkgs.buildNpmPackage {
    pname = "pierre-forgejo-frontend";
    version = "0.0.0";
    src = forgejoRoot + "/frontend";
    npmDepsHash = "sha256-q0qBatC/+nZuk2GtQE4ht3kK1cIRn4Lz1CAAM3SYSas=";
    installPhase = ''
      runHook preInstall
      mkdir -p $out/js
      cp -R dist/. $out/js/
      runHook postInstall
    '';
  };
in
{
  inherit frontend;

  nixosModule = forgejoRoot + "/pierre-ssr.nix";
  templates = forgejoRoot + "/templates";

  mkForgejoWithPierre =
    forgejoPackage:
    forgejoPackage.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        (forgejoRoot + "/patches/0001-pierre-ssr-highlighting.patch")
      ];
    });
}
