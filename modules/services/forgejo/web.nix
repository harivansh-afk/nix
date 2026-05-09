{
  pkgs,
  ...
}:
let
  noniconsFont = pkgs.fetchFromGitHub {
    owner = "ya2s";
    repo = "nonicons";
    rev = "a7d49eef27d1143b03a4eeb33859f411b9e93490";
    hash = "sha256-2eTjf7tl85YJkJY99Pb3a5PBhfPRUHIXXvAwfTPgnwc=";
  };
  frontend = pkgs.buildNpmPackage {
    pname = "harivan-forgejo-web-frontend";
    version = "0.0.0";
    src = ./frontend;
    npmDepsHash = "sha256-StwGQh7wbwhF8hC/Pqb7ROKyCGK3Rc6fXQYQ6JmOlZM=";
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
  assets = pkgs.runCommand "harivan-forgejo-web-assets" { } ''
    mkdir -p $out
    cp -R ${./assets}/. $out/
    mkdir -p $out/fonts
    cp ${noniconsFont}/dist/nonicons.woff $out/fonts/nonicons.woff
  '';
  templates = ./templates;
}
