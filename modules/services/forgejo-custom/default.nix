{
  pkgs,
  ...
}:
let
  frontend = pkgs.buildNpmPackage {
    pname = "harivan-forgejo-custom-frontend";
    version = "0.0.0";
    src = ./frontend;
    npmDepsHash = "sha256-OOjrTyt8AjZWGkVuqDTSw79xJBjcMrVLnj0cYfl968c=";
    installPhase = ''
      runHook preInstall
      mkdir -p $out/js
      cp dist/harivan-forgejo.js $out/js/
      runHook postInstall
    '';
  };
in
{
  inherit frontend;
  assets = ./assets;
  templates = ./templates;
}
