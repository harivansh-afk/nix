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
  assets = pkgs.runCommand "harivan-forgejo-web-assets" { } ''
    mkdir -p $out
    cp -R ${./assets}/. $out/
    mkdir -p $out/fonts
    cp ${noniconsFont}/dist/nonicons.woff $out/fonts/nonicons.woff
  '';
  templates = pkgs.runCommand "harivan-forgejo-web-templates" { } ''
    cp -R ${./templates}/. $out/
    chmod -R u+w $out

    version_for() {
      sha256sum "$1" | cut -c1-16
    }

    substituteInPlace $out/custom/header.tmpl \
      --replace-fail __HARIVAN_FORGEJO_CSS_VERSION__ "$(version_for ${assets}/css/harivan-forgejo.css)" \
      --replace-fail __HARIVAN_FORGEJO_PIERRE_PRELOAD_VERSION__ "$(version_for ${frontend}/js/pierre-preload.js)"

    substituteInPlace $out/custom/footer.tmpl \
      --replace-fail __HARIVAN_FORGEJO_JS_VERSION__ "$(version_for ${frontend}/js/harivan-forgejo.js)"
  '';
in
{
  inherit assets frontend templates;
}
