{
  forgejoPackage,
  pierreForgejo,
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
    npmDepsHash = "sha256-orNmifSF/ycAXTLBRNKSUuNaR3Dh24QkKCzbq3GMGd4=";
    installPhase = ''
      runHook preInstall
      mkdir -p $out/js
      cp -R dist/. $out/js/
      runHook postInstall
    '';
  };
  js = pkgs.runCommand "harivan-forgejo-web-js" { } ''
    mkdir -p $out/js
    cp -R ${frontend}/js/. $out/js/
    cp -R ${pierreForgejo.frontend}/js/. $out/js/
  '';
  assets = pkgs.runCommand "harivan-forgejo-web-assets" { } ''
    mkdir -p $out
    cp -R ${./assets}/. $out/
    mkdir -p $out/fonts
    cp ${noniconsFont}/dist/nonicons.woff $out/fonts/nonicons.woff
  '';
  templates = pkgs.runCommand "harivan-forgejo-web-templates" { } ''
    cp -R ${./templates}/. $out/
    chmod -R u+w $out

    mkdir -p $out/repo
    cp ${forgejoPackage.data}/templates/repo/commit_header.tmpl $out/repo/commit_header.tmpl
    cp ${forgejoPackage.data}/templates/repo/shabox_badge.tmpl $out/repo/shabox_badge.tmpl
    chmod u+w $out/repo/commit_header.tmpl $out/repo/shabox_badge.tmpl

    substituteInPlace $out/repo/commit_header.tmpl \
      --replace-fail \
        '{{ctx.AvatarUtils.AvatarByEmail .Verification.SigningEmail "" 28 "tw-mr-2"}}' \
        '<img loading="lazy" alt="" class="ui avatar tw-align-middle tw-mr-2" src="{{AppSubUrl}}/assets/img/forgejo.svg" title="Forgejo" width="28" height="28"/>'
    substituteInPlace $out/repo/shabox_badge.tmpl \
      --replace-fail \
        '{{ctx.AvatarUtils.AvatarByEmail .verification.SigningEmail "" 28}}' \
        '<img loading="lazy" alt="" class="ui avatar tw-align-middle" src="{{AppSubUrl}}/assets/img/forgejo.svg" title="Forgejo" width="28" height="28"/>'

    version_for() {
      sha256sum "$1" | cut -c1-16
    }

    substituteInPlace $out/custom/header.tmpl \
      --replace-fail __HARIVAN_FORGEJO_CSS_VERSION__ "$(version_for ${assets}/css/harivan-forgejo.css)"
    substituteInPlace $out/custom/header.tmpl \
      --replace-fail __PIERRE_FORGEJO_CSS_VERSION__ "$(version_for ${pierreForgejo.assets}/css/pierre-forgejo.css)"

    substituteInPlace $out/custom/footer.tmpl \
      --replace-fail __HARIVAN_FORGEJO_JS_VERSION__ "$(version_for ${js}/js/harivan-forgejo.js)"
    substituteInPlace $out/custom/footer.tmpl \
      --replace-fail __PIERRE_FORGEJO_JS_VERSION__ "$(version_for ${js}/js/pierre-forgejo.js)"
  '';
in
{
  inherit
    assets
    frontend
    js
    templates
    ;
}
